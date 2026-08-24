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
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            } else {
                intent.data
            }
        if (uri == null) return

        try {
            val resolver = contentResolver
            val displayName = queryDisplayName(resolver, uri) ?: "shared_file"
            val input = resolver.openInputStream(uri) ?: return
            val outDir = File(cacheDir, "shared")
            outDir.mkdirs()
            val outFile = File(outDir, "${System.currentTimeMillis()}_$displayName")
            input.use { stream ->
                outFile.outputStream().use { output -> stream.copyTo(output) }
            }
            pendingFile =
                mapOf(
                    "path" to outFile.absolutePath,
                    "name" to displayName,
                    "mime" to (intent.type ?: ""),
                )
        } catch (_: Exception) {
            pendingFile = null
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
