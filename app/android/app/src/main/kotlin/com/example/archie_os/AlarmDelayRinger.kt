package com.example.archie_os

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer

/**
 * Exit/entry delay beeps. [R.raw] is referenced directly so shrinking keeps the files.
 * Slow chirp loops until the last seconds, then the fast tail takes over.
 */
class AlarmDelayRinger(private val context: Context) {
    private var player: MediaPlayer? = null

    fun play(which: String, loop: Boolean) {
        stop()
        val res = when (which) {
            "fast" -> R.raw.alarm_delay_fast
            "double" -> R.raw.alarm_ack_double
            "triple" -> R.raw.alarm_ack_triple
            "armed" -> R.raw.alarm_armed_tone
            else -> R.raw.alarm_delay_slow
        }
        val created = MediaPlayer.create(context, res) ?: return
        created.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build(),
        )
        created.isLooping = loop
        created.setVolume(1f, 1f)
        created.setOnCompletionListener {
            if (player == it) {
                player = null
                it.release()
            }
        }
        created.start()
        player = created
    }

    fun stop() {
        val current = player
        player = null
        if (current == null) return
        try {
            if (current.isPlaying) current.stop()
        } catch (_: Exception) {
        }
        try {
            current.release()
        } catch (_: Exception) {
        }
    }
}
