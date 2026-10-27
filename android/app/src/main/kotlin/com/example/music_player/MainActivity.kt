package com.example.music_player

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngine
import com.ryanheise.audioservice.AudioServiceActivity
import java.io.File

class MainActivity : AudioServiceActivity() {
    private var pendingDeleteResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "music_player/local_audio")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "listSongs" -> {
                        Thread {
                            try {
                                val songs = queryLocalSongs()
                                runOnUiThread { result.success(songs) }
                            } catch (e: SecurityException) {
                                runOnUiThread { result.error("PERMISSION", e.message, null) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("SCAN", e.message, null) }
                            }
                        }.start()
                    }
                    "deleteSong" -> {
                        val mediaId = call.argument<Number>("mediaId")?.toLong()
                        if (mediaId == null || mediaId <= 0) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        val uri = ContentUris.withAppendedId(
                            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, mediaId
                        )
                        try {
                            val deleteRequest = MediaStore.createDeleteRequest(
                                contentResolver, listOf(uri)
                            )
                            pendingDeleteResult = result
                            startIntentSenderForResult(
                                deleteRequest.intentSender, REQUEST_DELETE, null, 0, 0, 0
                            )
                        } catch (e: ActivityNotFoundException) {
                            result.error("DELETE", e.message, null)
                        } catch (e: Exception) {
                            result.error("DELETE", e.message, null)
                        }
                    }
                    "saveToDownloads" -> {
                        val filename = call.argument<String>("filename")
                        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                        val bytes = call.argument<ByteArray>("bytes")
                        if (filename == null || bytes == null) {
                            result.error("ARGS", "filename and bytes required", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val path = saveToDownloads(filename, bytes, mimeType)
                                runOnUiThread { result.success(path) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("SAVE", e.message, null) }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_DELETE) {
            val r = pendingDeleteResult
            pendingDeleteResult = null
            r?.success(resultCode == Activity.RESULT_OK)
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun queryLocalSongs(): List<Map<String, Any?>> {
        val songs = mutableListOf<Map<String, Any?>>()
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.DATA,
        )
        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0"
        contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection,
            selection,
            null,
            "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC"
        )?.use { cursor ->
            val idIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val durationIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val dataIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
            while (cursor.moveToNext()) {
                val id = cursor.getLong(idIdx)
                val path = cursor.getString(dataIdx) ?: ""
                songs.add(
                    mapOf(
                        "id" to id,
                        "title" to (cursor.getString(titleIdx) ?: path.substringAfterLast('/')),
                        "artist" to cursor.getString(artistIdx),
                        "durationMs" to cursor.getLong(durationIdx),
                        "path" to path,
                        "uri" to "content://media/external/audio/media/$id",
                    )
                )
            }
        }
        return songs
    }

    /// Writes bytes into the public Download/Musicap folder. On Android 10+
    /// this goes through MediaStore so no storage permission is needed and
    /// the file is visible to file managers. Returns the absolute path.
    private fun saveToDownloads(filename: String, bytes: ByteArray, mimeType: String): String {
        val dirName = "Musicap"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, filename)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/" + dirName)
            }
            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("MediaStore insert failed")
            contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IllegalStateException("Could not open output stream")
            return Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                .absolutePath + "/" + dirName + "/" + filename
        } else {
            @Suppress("DEPRECATION")
            val dir = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                dirName
            )
            if (!dir.exists() && !dir.mkdirs()) {
                throw IllegalStateException("Could not create download folder")
            }
            val file = File(dir, filename)
            file.writeBytes(bytes)
            return file.absolutePath
        }
    }

    companion object {
        private const val REQUEST_DELETE = 2001
    }
}
