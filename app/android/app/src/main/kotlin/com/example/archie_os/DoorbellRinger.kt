package com.example.archie_os

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.MediaPlayer
import android.media.ToneGenerator
import android.os.Build
import android.util.Log
import kotlin.math.exp
import kotlin.math.sin

/**
 * Ding-dong on the wall-tablet speaker.
 *
 * Do not look up [R.raw.doorbell] by name: resource shrinking drops it.
 * Play generated PCM via [AudioTrack] first (no APK asset needed). WAV is extra.
 */
class DoorbellRinger(private val context: Context) {
    private val lock = Any()
    private var player: MediaPlayer? = null
    private var track: AudioTrack? = null
    private var worker: Thread? = null
    @Volatile private var running = false
    private var tone: ToneGenerator? = null
    private val saved = mutableListOf<Pair<Int, Int>>()
    private var savedSpeaker: Boolean? = null
    private var savedMode: Int? = null
    @Volatile private var gain = 0.8f

    fun start(volume: Float) {
        synchronized(lock) {
            stopLocked()
            gain = volume.coerceIn(0f, 1f)
            if (gain <= 0.001f) {
                Log.i(TAG, "doorbell volume 0 — not playing")
                return
            }
            boost()
            routeToSpeaker()
            requestFocus()
            running = true
            if (startWav()) {
                Log.i(TAG, "doorbell wav playing gain=$gain")
                return
            }
            if (startPcm()) {
                Log.i(TAG, "doorbell pcm playing gain=$gain")
                return
            }
            startToneFallback()
            Log.i(TAG, "doorbell tone fallback gain=$gain")
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
        val p = player
        player = null
        if (p != null) {
            try {
                if (p.isPlaying) p.stop()
            } catch (_: Exception) {
            }
            try {
                p.release()
            } catch (_: Exception) {
            }
        }
        val tg = tone
        tone = null
        try {
            tg?.release()
        } catch (_: Exception) {
        }
        restore()
    }

    /** Keep a compile-time reference so aapt cannot strip the wav. */
    @Suppress("unused")
    private val keepWav = R.raw.doorbell

    private fun startWav(): Boolean {
        return try {
            val afd = context.resources.openRawResourceFd(R.raw.doorbell) ?: return false
            val p = MediaPlayer()
            p.setAudioAttributes(mediaAttrs(AudioAttributes.USAGE_MEDIA))
            p.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
            afd.close()
            p.isLooping = true
            p.setVolume(gain, gain)
            p.prepare()
            p.start()
            player = p
            true
        } catch (e: Exception) {
            Log.w(TAG, "wav player failed", e)
            false
        }
    }

    private fun startPcm(): Boolean {
        val pcm = dingDongPcm()
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
                built.setVolume(gain)
                built.play()
                track = built
                worker = Thread({ writeLoop(built, pcm) }, "doorbell-pcm").also { it.start() }
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
                AudioManager.STREAM_MUSIC,
                (gain * 100).toInt().coerceIn(1, 100),
            )
            tone = tg
            worker = Thread({
                try {
                    while (running && !Thread.currentThread().isInterrupted) {
                        tg.startTone(ToneGenerator.TONE_PROP_BEEP2, 400)
                        Thread.sleep(2200)
                    }
                } catch (_: Exception) {
                }
            }, "doorbell-tone").also { it.start() }
        } catch (e: Exception) {
            Log.w(TAG, "tone fallback failed", e)
        }
    }

    private fun mediaAttrs(usage: Int): AudioAttributes {
        return AudioAttributes.Builder()
            .setUsage(usage)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .setLegacyStreamType(AudioManager.STREAM_MUSIC)
            .build()
    }

    private fun requestFocus() {
        val am = audio() ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                am.requestAudioFocus(
                    android.media.AudioFocusRequest.Builder(
                        AudioManager.AUDIOFOCUS_GAIN_TRANSIENT,
                    )
                        .setAudioAttributes(mediaAttrs(AudioAttributes.USAGE_ALARM))
                        .build(),
                )
            } else {
                @Suppress("DEPRECATION")
                am.requestAudioFocus(
                    null,
                    AudioManager.STREAM_ALARM,
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT,
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
            AudioManager.STREAM_MUSIC,
            AudioManager.STREAM_ALARM,
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
                val floor = 0.35f
                val scaled = (max * maxOf(gain, floor)).toInt().coerceAtLeast(1).coerceAtMost(max)
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
        private const val TAG = "DoorbellRinger"
        private const val SAMPLE_RATE = 44100

        private fun dingDongPcm(): ByteArray {
            fun tone(freq: Double, ms: Int, volume: Double): ShortArray {
                val n = SAMPLE_RATE * ms / 1000
                val out = ShortArray(n)
                val decay = 4.2
                for (i in 0 until n) {
                    val t = i.toDouble() / SAMPLE_RATE
                    val env = exp(-t * decay)
                    val s = (
                        sin(2.0 * Math.PI * freq * t) +
                            0.32 * sin(2.0 * Math.PI * freq * 2 * t) +
                            0.10 * sin(2.0 * Math.PI * freq * 3 * t)
                        ) / 1.42
                    val v = (s * env * volume * 32767.0).toInt().coerceIn(-32767, 32767)
                    out[i] = v.toShort()
                }
                return out
            }
            val ding = tone(783.99, 380, 0.92)
            val gap = ShortArray(SAMPLE_RATE * 140 / 1000)
            val dong = tone(659.25, 820, 0.95)
            val rest = ShortArray(SAMPLE_RATE * 1500 / 1000)
            val all = ding + gap + dong + rest
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
