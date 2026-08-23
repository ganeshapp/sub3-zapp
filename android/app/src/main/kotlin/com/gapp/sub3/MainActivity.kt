package com.gapp.sub3

import android.content.ContentValues
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Hosts the `com.gapp.sub3/exports` channel, which writes a file into the
 * phone's public Downloads folder. The Dart side sends raw bytes so binary
 * FIT files survive intact (TCX arrives UTF-8 encoded through the same path).
 * Direct writes to /Download are blocked from API 29 on, so this uses
 * MediaStore there and the public directory below that.
 */
class MainActivity : FlutterActivity() {

    private val exportsChannel = "com.gapp.sub3/exports"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, exportsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> {
                        val fileName = call.argument<String>("fileName")
                        val mimeType = call.argument<String>("mimeType")
                            ?: "application/octet-stream"
                        val bytes = call.argument<ByteArray>("bytes")
                        if (fileName.isNullOrEmpty() || bytes == null) {
                            result.error(
                                "BAD_ARGS",
                                "fileName and bytes are required",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(saveToDownloads(fileName, mimeType, bytes))
                        } catch (e: Exception) {
                            result.error(
                                "SAVE_FAILED",
                                e.message ?: "Could not write to the Downloads folder",
                                null,
                            )
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    /** Returns the user-facing path, e.g. `Download/Sub3_Hillview.tcx`. */
    private fun saveToDownloads(fileName: String, mimeType: String, bytes: ByteArray): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveViaMediaStore(fileName, mimeType, bytes)
        } else {
            saveToPublicDir(fileName, bytes)
        }
    }

    /**
     * API 29+: insert into MediaStore.Downloads while pending, stream the bytes
     * through the resolver, then publish. MediaStore de-duplicates names itself
     * (`file (1).tcx`), so no manual collision handling is needed here.
     */
    private fun saveViaMediaStore(fileName: String, mimeType: String, bytes: ByteArray): String {
        val resolver = contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, fileName)
            put(MediaStore.Downloads.MIME_TYPE, mimeType)
            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }

        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Could not create a file in Downloads")

        try {
            resolver.openOutputStream(uri).use { out ->
                if (out == null) throw IllegalStateException("Could not open Downloads for writing")
                out.write(bytes)
                out.flush()
            }
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }

        values.clear()
        values.put(MediaStore.Downloads.IS_PENDING, 0)
        resolver.update(uri, values, null, null)

        val savedName = resolver.query(
            uri,
            arrayOf(MediaStore.Downloads.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        } ?: fileName

        return "${Environment.DIRECTORY_DOWNLOADS}/$savedName"
    }

    /**
     * API < 29: write straight into the public Downloads directory and tell the
     * media scanner about it so the file shows up immediately.
     */
    private fun saveToPublicDir(fileName: String, bytes: ByteArray): String {
        val dir = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOWNLOADS,
        )
        if (!dir.exists() && !dir.mkdirs()) {
            throw IllegalStateException("Downloads folder is not available")
        }

        var target = File(dir, fileName)
        if (target.exists()) {
            val dot = fileName.lastIndexOf('.')
            val stem = if (dot > 0) fileName.substring(0, dot) else fileName
            val ext = if (dot > 0) fileName.substring(dot) else ""
            var n = 1
            while (target.exists()) {
                target = File(dir, "$stem ($n)$ext")
                n++
            }
        }

        target.writeBytes(bytes)
        MediaScannerConnection.scanFile(this, arrayOf(target.absolutePath), null, null)
        return "${Environment.DIRECTORY_DOWNLOADS}/${target.name}"
    }
}
