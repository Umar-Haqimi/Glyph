package my.umarh.glyph

import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.content.ComponentName
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.core.content.FileProvider
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.Closeable
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread

/**
 * Share / "Open with" intake (SPEC F2) and PGN export (F18), over two
 * MethodChannels. No plugin and no permission: content URIs carry their own
 * read grant.
 *
 * Intake (`my.umarh.glyph/intake`):
 *  - Dart calls `ready` once it listens. Anything that arrived before is then
 *    pushed with `shared`; later intents are pushed at once.
 *  - `shared` carries a map: `{kind: "text", text}`, `{kind: "file", bytes}`,
 *    `{kind: "tooLarge"}`, `{kind: "reading"}` (slow provider), `{kind: "timeout"}`
 *    (15 s) or `{kind: "error"}`.
 *  - Text (ACTION_SEND EXTRA_TEXT) is measured before it is sent. A stream
 *    (ACTION_VIEW data, ACTION_SEND EXTRA_STREAM) is read on a background
 *    daemon thread with a 15 s watchdog, never more than MAX_BYTES + one buffer, and never written to disk.
 *  - Intents arrive only from ShareIntakeActivity (the SEND / VIEW entry point, with a
 *    per-process token). An intent is handled once (a marker extra); one replayed from
 *    the recent-apps list (LAUNCHED_FROM_HISTORY) or restored after process death is ignored.
 *    Only `content:` URIs not served by Glyph itself are read.
 *
 * Export (`my.umarh.glyph/export`): `sharePgn(text, fileName, title)` writes the
 * PGN to the app's cache directory (sanitised name, older shares removed),
 * exposes it through a FileProvider content URI with a read grant and opens the
 * system share sheet. No storage permission.
 */
class MainActivity : FlutterActivity() {
    private var intake: MethodChannel? = null
    private var dartReady = false
    private val pending = ArrayList<Map<String, Any?>>()
    private val handler = Handler(Looper.getMainLooper())
    private var restored = false
    private var destroyed = false

    override fun onCreate(savedInstanceState: Bundle?) {
        // Process-death restore: Android hands back the intent that launched the
        // previous process. It was delivered then; never deliver it again.
        restored = savedInstanceState != null
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val channel = MethodChannel(messenger, INTAKE_CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> {
                    dartReady = true
                    flush()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        intake = channel
        MethodChannel(messenger, EXPORT_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "sharePgn" -> sharePgn(
                    call.argument<String>("text"),
                    call.argument<String>("fileName"),
                    call.argument<String>("title"),
                    result,
                )
                else -> result.notImplemented()
            }
        }
        if (!restored) handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    override fun onDestroy() {
        destroyed = true
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    // --- intake ---------------------------------------------------------------

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        try {
            // Only ShareIntakeActivity (same process) may hand over data: this
            // activity is exported for the launcher, so an explicit intent from
            // any app is ignored, and so is one restored after process death.
            if (intent.getStringExtra(IntakeGate.EXTRA_TOKEN) != IntakeGate.token) return
            if (intent.getBooleanExtra(HANDLED, false)) return
            if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
            val action = intent.action
            if (action != Intent.ACTION_SEND && action != Intent.ACTION_VIEW) return
            intent.putExtra(HANDLED, true)

            if (action == Intent.ACTION_SEND) {
                if (intent.getBooleanExtra(IntakeGate.EXTRA_TOO_LARGE, false)) {
                    deliver(mapOf("kind" to "tooLarge"))
                    return
                }
                val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
                if (text != null && text.isNotBlank()) {
                    // Binder already limits extras to about 1 MB; measure anyway.
                    if (text.toByteArray(Charsets.UTF_8).size > MAX_BYTES) {
                        deliver(mapOf("kind" to "tooLarge"))
                    } else {
                        deliver(mapOf("kind" to "text", "text" to text))
                    }
                    return
                }
            }
            val uri = if (action == Intent.ACTION_VIEW) intent.data else streamExtra(intent)
            if (uri == null) return
            if (!IntakeGate.isAcceptable(uri, packageName)) return
            readAsync(uri)
        } catch (e: Exception) {
            // A malformed intent (bad extras, a hostile parcel): nothing to import.
            deliver(mapOf("kind" to "error"))
        }
    }

    /**
     * Reads [uri] on its own daemon thread (a stalled provider blocks that
     * thread only, never a later share). A watchdog gives up after
     * READ_TIMEOUT_MS: it closes the stream and delivers `timeout`; whatever the
     * thread produces afterwards is dropped. `reading` is sent when the read
     * takes longer than READING_DELAY_MS, so Dart can show a progress note.
     */
    private fun readAsync(uri: Uri) {
        val done = AtomicBoolean(false)
        val open = AtomicReference<Closeable?>(null)
        val showReading = Runnable { if (!done.get()) deliver(mapOf("kind" to "reading")) }
        val watchdog = Runnable {
            if (done.compareAndSet(false, true)) {
                handler.removeCallbacks(showReading)
                try { open.get()?.close() } catch (e: Exception) { /* best effort */ }
                deliver(mapOf("kind" to "timeout"))
            }
        }
        handler.postDelayed(showReading, READING_DELAY_MS)
        handler.postDelayed(watchdog, READ_TIMEOUT_MS)
        thread(name = "glyph-intake-read", isDaemon = true) {
            val message = readCapped(uri, done, open)
            runOnUiThread {
                if (!destroyed && done.compareAndSet(false, true)) {
                    handler.removeCallbacks(showReading)
                    handler.removeCallbacks(watchdog)
                    deliver(message)
                }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun streamExtra(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        }

    /** Reads at most MAX_BYTES; a larger source gives `tooLarge` without keeping the bytes. */
    private fun readCapped(uri: Uri, done: AtomicBoolean, open: AtomicReference<Closeable?>): Map<String, Any?> {
        return try {
            val input = contentResolver.openInputStream(uri) ?: return mapOf("kind" to "error")
            open.set(input)
            if (done.get()) { // the watchdog fired while the provider was still opening it
                input.close()
                return mapOf("kind" to "error")
            }
            input.use { stream ->
                val out = ByteArrayOutputStream()
                val buffer = ByteArray(16 * 1024)
                var total = 0
                while (true) {
                    val n = stream.read(buffer)
                    if (n < 0) break
                    total += n
                    if (total > MAX_BYTES) return mapOf("kind" to "tooLarge")
                    out.write(buffer, 0, n)
                }
                mapOf("kind" to "file", "bytes" to out.toByteArray())
            }
        } catch (e: Exception) {
            // SecurityException (no grant), FileNotFoundException, IOException, ...
            mapOf("kind" to "error")
        }
    }

    private fun deliver(message: Map<String, Any?>) {
        if (dartReady) {
            intake?.invokeMethod("shared", message)
        } else {
            pending.add(message)
        }
    }

    private fun flush() {
        val copy = ArrayList(pending)
        pending.clear()
        for (message in copy) intake?.invokeMethod("shared", message)
    }

    // --- export ---------------------------------------------------------------

    private fun sharePgn(text: String?, fileName: String?, title: String?, result: MethodChannel.Result) {
        if (text == null || fileName == null) {
            result.error("bad_arguments", null, null)
            return
        }
        try {
            // Sanitised again here: the name comes over a channel.
            var safe = fileName.replace(Regex("[^A-Za-z0-9._-]"), "_").trim('.', '_', '-').take(80)
            if (safe.isEmpty()) safe = "game.pgn"
            val dir = File(cacheDir, SHARE_DIR)
            dir.mkdirs()
            dir.listFiles()?.forEach { it.delete() }
            val file = File(dir, safe)
            file.writeText(text, Charsets.UTF_8)
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            val send = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_STREAM, uri)
                // A very large PGN stays out of the intent (binder limit): the file carries it.
                if (text.length <= MAX_EXTRA_TEXT_CHARS && text.toByteArray(Charsets.UTF_8).size <= MAX_EXTRA_TEXT_BYTES) {
                    putExtra(Intent.EXTRA_TEXT, text)
                }
                putExtra(Intent.EXTRA_SUBJECT, safe)
                clipData = ClipData.newRawUri(safe, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            val chooser = Intent.createChooser(send, title)
            // Glyph itself is not a target of its own Export (its intake activity accepts text/plain).
            chooser.putExtra(
                Intent.EXTRA_EXCLUDE_COMPONENTS,
                arrayOf(
                    ComponentName(this, ShareIntakeActivity::class.java),
                    ComponentName(this, MainActivity::class.java),
                ),
            )
            startActivity(chooser)
            result.success(null)
        } catch (e: Exception) {
            result.error("share_failed", null, null)
        }
    }

    companion object {
        private const val INTAKE_CHANNEL = "my.umarh.glyph/intake"
        private const val EXPORT_CHANNEL = "my.umarh.glyph/export"
        private const val HANDLED = "my.umarh.glyph.HANDLED"
        private const val SHARE_DIR = "shared_pgn"

        /** Limits.maxPgnBytes in glyph_core: 2 MB. */
        private const val MAX_BYTES = 2 * 1024 * 1024

        /** A stalled provider is given up on after this long (the user gets an error). */
        private const val READ_TIMEOUT_MS = 15_000L

        /** A read slower than this is reported to Dart as `reading`. */
        private const val READING_DELAY_MS = 400L

        /** Export puts the PGN into EXTRA_TEXT only up to 100 KB; the file always carries it. */
        private const val MAX_EXTRA_TEXT_BYTES = 100 * 1024
        private const val MAX_EXTRA_TEXT_CHARS = 100 * 1024
    }
}
