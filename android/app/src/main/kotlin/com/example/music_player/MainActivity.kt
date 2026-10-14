package com.example.music_player

import android.provider.MediaStore
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngine
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {
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
                    else -> result.notImplemented()
                }
            }
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
}
