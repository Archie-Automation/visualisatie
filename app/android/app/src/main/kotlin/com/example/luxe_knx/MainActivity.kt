package com.example.luxe_knx

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Wandtablet wake:
 * - Proximity-sensor indien aanwezig
 * - Anders lichtsensor: snelle donkere dip = hand over sensor → wake
 * - [wakeScreen] ook aanroepbaar vanuit Flutter (alarm-inloop etc.)
 */
class MainActivity : FlutterActivity(), SensorEventListener {
    private var sensorManager: SensorManager? = null
    private var proximitySensor: Sensor? = null
    private var lightSensor: Sensor? = null
    private var proximityEvents: EventChannel.EventSink? = null
    private var isNear = false
    private var lastLight: Float? = null
    private var lastWakeAtMs = 0L
    private val mainHandler = Handler(Looper.getMainLooper())
    private var wakeLock: PowerManager.WakeLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "luxe_knx/proximity_events",
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                proximityEvents = events
                startSensors()
            }

            override fun onCancel(arguments: Any?) {
                stopSensors()
                proximityEvents = null
            }
        })

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "luxe_knx/proximity",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "wakeScreen" -> {
                    wakeScreen()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun wakeScreen() {
        val now = System.currentTimeMillis()
        if (now - lastWakeAtMs < 800) return
        lastWakeAtMs = now

        runOnUiThread {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setTurnScreenOn(true)
                setShowWhenLocked(true)
            }
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD,
            )
        }

        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        @Suppress("DEPRECATION")
        val wl = pm.newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                PowerManager.ACQUIRE_CAUSES_WAKEUP or
                PowerManager.ON_AFTER_RELEASE,
            "luxe_knx:wake",
        )
        wl.setReferenceCounted(false)
        // Timeout-release — niet meteen release() (dat annuleerde de wake).
        wl.acquire(5000)
        wakeLock = wl
        mainHandler.postDelayed({
            try {
                if (wl.isHeld) wl.release()
            } catch (_: Exception) {
            }
            if (wakeLock === wl) wakeLock = null
        }, 5000)
    }

    private fun emitNear() {
        wakeScreen()
        mainHandler.post {
            proximityEvents?.success("near")
        }
    }

    private fun startSensors() {
        val sm = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        sensorManager = sm
        proximitySensor = sm.getDefaultSensor(Sensor.TYPE_PROXIMITY)
        lightSensor = sm.getDefaultSensor(Sensor.TYPE_LIGHT)

        proximitySensor?.let {
            sm.registerListener(this, it, SensorManager.SENSOR_DELAY_UI)
        }
        // Tablet/paneel zonder proximity: hand over lichtsensor.
        if (proximitySensor == null) {
            lightSensor?.let {
                sm.registerListener(this, it, SensorManager.SENSOR_DELAY_UI)
            }
        }
    }

    private fun stopSensors() {
        sensorManager?.unregisterListener(this)
        lastLight = null
        isNear = false
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null) return
        when (event.sensor.type) {
            Sensor.TYPE_PROXIMITY -> {
                val value = event.values[0]
                val max = event.sensor.maximumRange
                // Near: 0 of duidelijk onder maxRange (binary of continuous).
                val near = value < max * 0.5f || value <= 0.1f
                if (near && !isNear) {
                    isNear = true
                    emitNear()
                } else if (!near) {
                    isNear = false
                }
            }
            Sensor.TYPE_LIGHT -> {
                val lux = event.values[0]
                val prev = lastLight
                lastLight = lux
                if (prev == null) return
                // Snelle afname: hand dicht bij / over de lichtsensor.
                val covered = lux < 8f && prev > 40f && lux < prev * 0.25f
                if (covered) emitNear()
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun onDestroy() {
        stopSensors()
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
        }
        wakeLock = null
        super.onDestroy()
    }
}
