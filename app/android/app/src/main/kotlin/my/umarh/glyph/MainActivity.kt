package my.umarh.glyph

import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.core.content.FileProvider
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

/**
 * Share / "Open with" intake (SPEC F2) and PGN export (F18), over two
 * MethodChannels. No plugin and no permission: content URIs carry their own
 * read grant.
 *
 * Intake (`my.umarh.glyph/intake`):
 *  - Dart calls `ready` once it listens. Anything that arrived before is then
 *    pushed with `shared`; later intents are pushed at once.
 *  - `shared` carries a map: `{kind: "text", text}`, `{kind: "file", bytes}`,
 *    `{kind: "tooLarge"}` or `{kind: "error"}`.
 *  - Text (ACTION_SEND EXTRA_TEXT) is measured before it is sent. A stream
 *    (ACTION_VIEW data, ACTION_SEND EXTRA_STREAM) is read on a background
 *    thread, never more than MAX_BYTES + one buffer, and never written to disk.
 *  - An intent is handled once (a marker extra), and one that Android replays
 *    from the recent-apps list (LAUNCHED_FROM_HISTORY) is ignored.
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
    private val reader = Executors.newSingleThreadExecutor()

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
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    override fun onDestroy() {
        reader.shutdown()
        super.onDestroy()
    }

    // --- intake ---------------------------------------------------------------

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        try {
            if (intent.getBooleanExtra(HANDLED, false)) return
            if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
            val action = intent.action
            if (action != Intent.ACTION_SEND && action != Intent.ACTION_VIEW) return
            intent.putExtra(HANDLED, true)

            if (action == Intent.ACTION_SEND) {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)
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
            val scheme = uri.scheme
            if (scheme != "content" && scheme != "file") return
            reader.execute {
                val message = readCapped(uri)
                runOnUiThread { deliver(message) }
            }
        } catch (e: Exception) {
            // A malformed intent (bad extras, a hostile parcel): nothing to import.
            deliver(mapOf("kind" to "error"))
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
    private fun readCapped(uri: Uri): Map<String, Any?> {
        return try {
            val input = contentResolver.openInputStream(uri) ?: return mapOf("kind" to "error")
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
                putExtra(Intent.EXTRA_TEXT, text)
                putExtra(Intent.EXTRA_SUBJECT, safe)
                clipData = ClipData.newRawUri(safe, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(send, title))
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
    }
}
