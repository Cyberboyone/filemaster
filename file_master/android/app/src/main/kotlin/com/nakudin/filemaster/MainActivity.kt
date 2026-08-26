package com.nakudin.filemaster

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.nakudin.filemaster/file_open"
    private var methodChannel: MethodChannel? = null
    private var pendingFile: Map<String, Any?>? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            if (call.method == "getInitialFile") {
                result.success(pendingFile)
                pendingFile = null
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
        // App already running: forward the incoming file to Flutter.
        pendingFile?.let { file -> methodChannel?.invokeMethod("onFileOpened", file) }
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        if (action != Intent.ACTION_VIEW && action != Intent.ACTION_SEND) return

        val uri: Uri? =
            if (action == Intent.ACTION_SEND) {
                intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            } else {
                intent.data
            }
        if (uri == null) return

        try {
            val isFileScheme = uri.scheme == "file"
            val rawName =
                if (isFileScheme) {
                    uri.lastPathSegment ?: "shared_file"
                } else {
                    queryDisplayName(contentResolver, uri) ?: "shared_file"
                }
            val mime = intent.type
            val finalName = ensureExtension(rawName, mime)

            val outFile =
                if (isFileScheme) {
                    val p = uri.path
                    if (p.isNullOrEmpty()) return
                    File(p)
                } else {
                    // Persist to the app's external files dir (survives restarts,
                    // unlike cacheDir) so the file can be re-opened from Recents.
                    val baseDir = getExternalFilesDir(null) ?: cacheDir
                    val outDir = File(baseDir, "shared")
                    outDir.mkdirs()
                    val target =
                        File(outDir, "${System.currentTimeMillis()}_$finalName")
                    val input = contentResolver.openInputStream(uri) ?: return
                    input.use { stream ->
                        target.outputStream().use { out -> stream.copyTo(out) }
                    }
                    target
                }

            pendingFile =
                mapOf(
                    "path" to outFile.absolutePath,
                    "name" to finalName,
                    "mime" to (mime ?: ""),
                )
        } catch (_: Exception) {
            pendingFile = null
        }
    }

    /** Appends an extension derived from the mime type when the name lacks one. */
    private fun ensureExtension(name: String, mime: String?): String {
        if (name.contains('.')) return name
        val ext = mimeToExtension(mime)
        return if (ext != null) "$name.$ext" else name
    }

    private fun mimeToExtension(mime: String?): String? {
        return when (mime) {
            "application/pdf" -> "pdf"
            "application/msword" -> "doc"
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document" -> "docx"
            "application/vnd.ms-excel" -> "xls"
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" -> "xlsx"
            "application/vnd.ms-powerpoint" -> "ppt"
            "application/vnd.openxmlformats-officedocument.presentationml.presentation" -> "pptx"
            "application/rtf" -> "rtf"
            "application/vnd.oasis.opendocument.text" -> "odt"
            "application/vnd.oasis.opendocument.spreadsheet" -> "ods"
            "application/vnd.oasis.opendocument.presentation" -> "odp"
            "text/plain" -> "txt"
            "text/csv" -> "csv"
            "application/zip" -> "zip"
            "application/x-rar-compressed" -> "rar"
            "application/x-7z-compressed" -> "7z"
            "application/gzip" -> "gz"
            "image/png" -> "png"
            "image/jpeg" -> "jpg"
            "image/gif" -> "gif"
            "image/bmp" -> "bmp"
            "image/webp" -> "webp"
            "image/heic" -> "heic"
            "image/tiff" -> "tiff"
            else -> null
        }
    }

    private fun queryDisplayName(
        resolver: android.content.ContentResolver,
        uri: Uri,
    ): String? {
        var name: String? = null
        try {
            val cursor = resolver.query(uri, null, null, null, null)
            cursor?.use {
                val index = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0 && it.moveToFirst()) name = it.getString(index)
            }
        } catch (_: Exception) {
            // Ignore – fall back to the default name.
        }
        return name
    }
}
