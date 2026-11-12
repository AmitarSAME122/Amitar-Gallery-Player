package com.amitar.amitar_gallery_player

import android.content.ContentResolver
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val contentUriExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CONTENT_URI_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "copyToCache") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val uri = call.argument<String>("uri")
            val maxBytes = call.argument<Number>("maxBytes")?.toLong()
            if (
                uri.isNullOrBlank() ||
                maxBytes == null ||
                maxBytes <= 0L ||
                maxBytes > MAX_COPY_BYTES
            ) {
                result.error(
                    "INVALID_CONTENT_URI_REQUEST",
                    "A content URI and maxBytes between 1 byte and 256 MiB are required.",
                    null,
                )
                return@setMethodCallHandler
            }

            contentUriExecutor.execute {
                try {
                    val copiedPath = copyContentUriToCache(uri, maxBytes)
                    runOnUiThread { result.success(copiedPath) }
                } catch (error: Exception) {
                    runOnUiThread {
                        result.error(
                            "CONTENT_URI_COPY_FAILED",
                            error.localizedMessage ?: "Unable to read the selected content URI.",
                            null,
                        )
                    }
                }
            }
        }
    }

    private fun copyContentUriToCache(uriValue: String, maxBytes: Long): String {
        val uri = Uri.parse(uriValue)
        require(uri.scheme?.equals(ContentResolver.SCHEME_CONTENT, ignoreCase = true) == true) {
            "Only content:// URIs can be read by this bridge."
        }
        require(maxBytes > 0L) { "The maximum byte count must be positive." }

        val destination = File(cacheDir, "amitar-content-${UUID.randomUUID()}.bin")
        try {
            val input = contentResolver.openInputStream(uri)
                ?: throw IOException("Android could not open the selected content URI.")
            input.use { source ->
                FileOutputStream(destination).use { target ->
                    val buffer = ByteArray(COPY_BUFFER_BYTES)
                    var totalBytes = 0L
                    while (true) {
                        val count = source.read(buffer)
                        if (count < 0) break
                        if (count == 0) continue
                        if (totalBytes > maxBytes - count.toLong()) {
                            throw IOException("The selected file exceeds the allowed read size.")
                        }
                        target.write(buffer, 0, count)
                        totalBytes += count
                    }
                    target.flush()
                }
            }
            if (!destination.isFile) {
                throw IOException("Android did not create the temporary content copy.")
            }
            return destination.absolutePath
        } catch (error: Exception) {
            destination.delete()
            throw error
        }
    }

    override fun onDestroy() {
        contentUriExecutor.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val CONTENT_URI_CHANNEL =
            "com.amitar.amitar_gallery_player/content_uri"
        private const val COPY_BUFFER_BYTES = 64 * 1024
        private const val MAX_COPY_BYTES = 256L * 1024L * 1024L
    }
}
