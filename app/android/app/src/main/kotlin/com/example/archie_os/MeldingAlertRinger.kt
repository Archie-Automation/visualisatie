package com.example.archie_os

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.ToneGenerator
import android.os.Build
import android.util.Log
import kotlin.math.sin

/**
 * Repeating two-tone alarm for urgent KNX meldingen on the wall tablet.
 * Independent of [DoorbellRinger] (ding-dong).
 */
class MeldingAlertRinger(private val context: Context) {
    private val lock = Any()
    private var track: AudioTrack? = null
    private var worker: Thread? = null
    @Volatile private var running = false
    private var tone: ToneGenerator? = null
    private val saved = mutableListOf<Pair<Int, Int>>()
    private var savedSpeaker: Boolean? = null
    private var savedMode: Int? = null

    fun start() {
        synchronized(lock) {
            stopLocked()
            boost()
            routeToSpeaker()
            requestFocus()
            running = true
            if (startPcm()) {
                Log.i(TAG, "melding alert pcm playing")
                return
            }
            startToneFallback()
            Log.i(TAG, "melding alert tone fallback")
        }
    }

    fun stop() {
        synchronized(lock) {
            stopLocked()
        }
    }

    private fun stopLocked() {
        running = false
        worker?.interrupt()
        worker = null
        val t = track
        track = null
        if (t != null) {
            try {
                t.pause()
            } catch (_: Exception) {
            }
            try {
                t.flush()
            } catch (_: Exception) {
            }
            try {
                t.release()
            } catch (_: Exception) {
            }
        }
        try {
            tone?.stopTone()
        } catch (_: Exception) {
        }
        try {
            tone?.release()
        } catch (_: Exception) {
        }
        tone = null
        restore()
    }

    private fun startPcm(): Boolean {
        val pcm = alertPcm()
        val tries = listOf(
            Triple(
                AudioAttributes.USAGE_ALARM,
                AudioManager.STREAM_ALARM,
                AudioAttributes.FLAG_AUDIBILITY_ENFORCED,
            ),
            Triple(AudioAttributes.USAGE_MEDIA, AudioManager.STREAM_MUSIC, 0),
            Triple(
                AudioAttributes.USAGE_NOTIFICATION_RINGTONE,
                AudioManager.STREAM_RING,
                0,
            ),
        )
        for ((usage, stream, flags) in tries) {
            val built = buildTrack(usage, stream, flags) ?: continue
            try {
                built.setVolume(0.95f)
                built.play()
                track = built
                worker = Thread({ writeLoop(built, pcm) }, "melding-alert-pcm")
                    .also { it.start() }
                return true
            } catch (e: Exception) {
                Log.w(TAG, "pcm start failed usage=$usage", e)
                try {
                    built.release()
                } catch (_: Exception) {
                }
            }
        }
        return false
    }

    private fun buildTrack(
        usage: Int,
        stream: Int,
        flags: Int,
    ): AudioTrack? {
        val min = AudioTrack.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        if (min <= 0) return null
        val buf = maxOf(min, 4096)
        val attrs = AudioAttributes.Builder()
            .setUsage(usage)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .setLegacyStreamType(stream)
            .apply { if (flags != 0) setFlags(flags) }
            .build()
        val format = AudioFormat.Builder()
            .setSampleRate(SAMPLE_RATE)
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
            .build()
        return try {
            AudioTrack.Builder()
                .setAudioAttributes(attrs)
                .setAudioFormat(format)
                .setBufferSizeInBytes(buf)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
        } catch (e: Exception) {
            Log.w(TAG, "AudioTrack build failed usage=$usage", e)
            null
        }
    }

    private fun writeLoop(t: AudioTrack, pcm: ByteArray) {
        var offset = 0
        try {
            while (running && !Thread.currentThread().isInterrupted) {
                val n = minOf(4096, pcm.size - offset)
                val written = t.write(pcm, offset, n)
                if (written < 0) break
                offset += written
                if (offset >= pcm.size) offset = 0
            }
        } catch (_: Exception) {
        }
    }

    private fun startToneFallback() {
        try {
            val tg = ToneGenerator(
                AudioManager.STREAM_ALARM,
                90,
            )
            tone = tg
            worker = Thread({
                try {
                    while (running && !Thread.currentThread().isInterrupted) {
                        tg.startTone(ToneGenerator.TONE_CDMA_HIGH_L, 180)
                        Thread.sleep(260)
                        tg.startTone(ToneGenerator.TONE_CDMA_HIGH_L, 180)
                        Thread.sleep(700)
                    }
                } catch (_: Exception) {
                }
            }, "melding-alert-tone").also { it.start() }
        } catch (e: Exception) {
            Log.w(TAG, "tone fallback failed", e)
        }
    }

    private fun mediaAttrs(usage: Int): AudioAttributes {
        return AudioAttributes.Builder()
            .setUsage(usage)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .setLegacyStreamType(AudioManager.STREAM_ALARM)
            .build()
    }

    private fun requestFocus() {
        val am = audio() ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                am.requestAudioFocus(
                    android.media.AudioFocusRequest.Builder(
                        AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK,
                    )
                        .setAudioAttributes(mediaAttrs(AudioAttributes.USAGE_ALARM))
                        .build(),
                )
            } else {
                @Suppress("DEPRECATION")
                am.requestAudioFocus(
                    null,
                    AudioManager.STREAM_ALARM,
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK,
                )
            }
        } catch (_: Exception) {
        }
    }

    private fun routeToSpeaker() {
        val am = audio() ?: return
        try {
            savedMode = am.mode
            savedSpeaker = am.isSpeakerphoneOn
            am.mode = AudioManager.MODE_NORMAL
            @Suppress("DEPRECATION")
            am.isSpeakerphoneOn = true
        } catch (_: Exception) {
        }
    }

    private fun boost() {
        if (saved.isNotEmpty()) return
        val am = audio() ?: return
        val streams = intArrayOf(
            AudioManager.STREAM_ALARM,
            AudioManager.STREAM_MUSIC,
            AudioManager.STREAM_RING,
            AudioManager.STREAM_NOTIFICATION,
            AudioManager.STREAM_SYSTEM,
        )
        for (stream in streams) {
            try {
                val max = am.getStreamMaxVolume(stream)
                if (max <= 0) continue
                val cur = am.getStreamVolume(stream)
                saved.add(stream to cur)
                val scaled = (max * 0.85f).toInt().coerceAtLeast(1).coerceAtMost(max)
                if (cur < scaled) am.setStreamVolume(stream, scaled, 0)
            } catch (_: Exception) {
            }
        }
    }

    private fun restore() {
        val am = audio()
        val copy = saved.toList()
        saved.clear()
        if (am == null) return
        for ((stream, volume) in copy) {
            try {
                am.setStreamVolume(stream, volume, 0)
            } catch (_: Exception) {
            }
        }
        try {
            val sp = savedSpeaker
            if (sp != null) {
                @Suppress("DEPRECATION")
                am.isSpeakerphoneOn = sp
            }
            val mode = savedMode
            if (mode != null) am.mode = mode
        } catch (_: Exception) {
        }
        savedSpeaker = null
        savedMode = null
    }

    private fun audio(): AudioManager? {
        return context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
    }

    companion object {
        private const val TAG = "MeldingAlert"
        private const val SAMPLE_RATE = 44100

        private fun alertPcm(): ByteArray {
            fun tone(freq: Double, ms: Int): ShortArray {
                val n = SAMPLE_RATE * ms / 1000
                val out = ShortArray(n)
                for (i in 0 until n) {
                    val t = i.toDouble() / SAMPLE_RATE
                    val fade = when {
                        i < 80 -> i / 80.0
                        i > n - 80 -> (n - i) / 80.0
                        else -> 1.0
                    }
                    val s = sin(2.0 * Math.PI * freq * t) * fade * 0.72
                    out[i] = (s * 32767.0).toInt().coerceIn(-32767, 32767).toShort()
                }
                return out
            }
            fun silence(ms: Int) = ShortArray(SAMPLE_RATE * ms / 1000)
            val all = tone(880.0, 180) + silence(70) +
                tone(1174.7, 180) + silence(520)
            val bytes = ByteArray(all.size * 2)
            var o = 0
            for (s in all) {
                bytes[o++] = (s.toInt() and 0xff).toByte()
                bytes[o++] = (s.toInt() shr 8).toByte()
            }
            return bytes
        }
    }
}
