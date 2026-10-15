package com.example.music_player

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ContentUris
import android.content.Intent
import android.provider.MediaStore
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngine
import com.ryanheise.audioservice.AudioServiceActivity

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

    companion object {
        private const val REQUEST_DELETE = 2001
    }
}
