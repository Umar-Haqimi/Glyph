package my.umarh.glyph

import android.app.Activity
import android.content.ClipData
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import java.util.UUID

/**
 * The only entry point of Share and "Open with" (SPEC F2); it has no UI and no
 * Flutter. A chooser starts its target in the sender's task, so a Flutter
 * activity declared for SEND / VIEW would run a second FlutterEngine (second
 * `main()`, second sqlite connection, second Stockfish) inside the same
 * process. This activity checks the payload, forwards it to [MainActivity]
 * (NEW_TASK | CLEAR_TOP | SINGLE_TOP, so the one running instance gets it in
 * `onNewIntent`, or the app starts cold in its own task) and finishes at once.
 *
 * [MainActivity] must be exported for the launcher, so anyone can send it an
 * explicit intent; it therefore acts only on intents carrying [IntakeGate.token],
 * a random value that exists in this process only.
 */
class ShareIntakeActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            forward(intent)
        } catch (e: Exception) {
            // A malformed intent (bad extras, a hostile parcel): nothing to import.
        }
        finish()
    }

    private fun forward(source: Intent?) {
        if (source == null) return
        val action = source.action
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_VIEW) return
        val out = Intent(action).apply {
            component = ComponentName(this@ShareIntakeActivity, MainActivity::class.java)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra(IntakeGate.EXTRA_TOKEN, IntakeGate.token)
        }
        var uri: Uri? = null
        if (action == Intent.ACTION_SEND) {
            val text = source.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
            if (text != null && text.isNotBlank()) {
                if (text.length > IntakeGate.MAX_BYTES || text.toByteArray(Charsets.UTF_8).size > IntakeGate.MAX_BYTES) {
                    out.putExtra(IntakeGate.EXTRA_TOO_LARGE, true)
                } else {
                    out.putExtra(Intent.EXTRA_TEXT, text)
                }
            } else {
                uri = streamExtra(source)
            }
        } else {
            uri = source.data
        }
        if (uri != null) {
            if (!IntakeGate.isAcceptable(uri, packageName)) return
            if (action == Intent.ACTION_SEND) out.putExtra(Intent.EXTRA_STREAM, uri) else out.data = uri
            out.clipData = ClipData.newRawUri("", uri)
            out.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } else if (!out.hasExtra(Intent.EXTRA_TEXT) && !out.hasExtra(IntakeGate.EXTRA_TOO_LARGE)) {
            return
        }
        startActivity(out)
    }

    @Suppress("DEPRECATION")
    private fun streamExtra(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        }
}

/** What both activities agree on. */
object IntakeGate {
    /** Limits.maxPgnBytes in glyph_core: 2 MB. */
    const val MAX_BYTES = 2 * 1024 * 1024

    const val EXTRA_TOKEN = "my.umarh.glyph.INTAKE_TOKEN"
    const val EXTRA_TOO_LARGE = "my.umarh.glyph.TOO_LARGE"

    /** Random per process: a forged explicit intent cannot know it, and a restored intent from a dead process carries a stale one. */
    val token: String = UUID.randomUUID().toString()

    /**
     * Only `content:` URIs, and never one served by this app (its own
     * FileProvider, or any authority under its package name): another app must
     * not be able to make Glyph read its own files.
     */
    fun isAcceptable(uri: Uri, packageName: String): Boolean {
        if (uri.scheme != "content") return false
        val authority = (uri.authority ?: return false).substringAfterLast('@').lowercase()
        val own = packageName.lowercase()
        if (authority.isEmpty()) return false
        if (authority == own || authority.startsWith("$own.")) return false
        return true
    }
}
