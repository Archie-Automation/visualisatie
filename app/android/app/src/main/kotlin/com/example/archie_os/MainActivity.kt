package com.example.archie_os

import android.content.Context
import android.graphics.PixelFormat
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Wandtablet wake:
 * - Proximity-sensor indien aanwezig
 * - Anders lichtsensor: snelle donkere dip = hand over sensor → wake
 * - [wakeScreen] ook aanroepbaar vanuit Flutter (alarm-inloop etc.)
 * - APK-update via PackageInstaller-sessie (GitHub OTA via NUC)
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
    private var apkInstaller: ApkInstaller? = null
    private var doorbellRinger: DoorbellRinger? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "archie_os/proximity_events",
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
            "archie_os/proximity",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "wakeScreen" -> {
                    wakeScreen()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        doorbellRinger = DoorbellRinger(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "archie_os/doorbell",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val volume = (call.argument<Number>("volume") ?: 0.8).toFloat()
                    doorbellRinger?.start(volume)
                    result.success(null)
                }
                "stop" -> {
                    doorbellRinger?.stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        apkInstaller = ApkInstaller(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "archie_os/apk_install",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("bad_args", "path required", null)
                        return@setMethodCallHandler
                    }
                    apkInstaller?.install(path, result)
                }
                "appVersion" -> {
                    result.success(currentAppVersion())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun currentAppVersion(): Map<String, Any> {
        val p = packageManager.getPackageInfo(packageName, 0)
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            p.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            p.versionCode.toLong()
        }
        return mapOf(
            "versionName" to (p.versionName ?: ""),
            "versionCode" to code,
        )
    }

    private fun wakeScreen() {
        val now = System.currentTimeMillis()
        // Short debounce — was 800ms and felt sluggish on wall panels.
        if (now - lastWakeAtMs < 250) return
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
            "archie_os:wake",
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

        // FASTEST: wall tablets need snappy hand-approach wake.
        val rate = SensorManager.SENSOR_DELAY_FASTEST
        proximitySensor?.let { sm.registerListener(this, it, rate) }
        // Always also listen to light — many panels have weak/missing proximity.
        lightSensor?.let { sm.registerListener(this, it, rate) }
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
                val near = value < max * 0.65f || value <= 0.5f
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
                // Hand over / dichtbij sensor: snelle dip in lux.
                // Mildere drempels dan voorheen (8/40/0.25) — reageerde te traag.
                val sharpDrop = lux < prev * 0.4f && (prev - lux) >= 12f
                val covered = lux < 25f && prev > 18f && sharpDrop
                if (covered) emitNear()
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    override fun onCreate(savedInstanceState: Bundle?) {
        // 32-bit color path — reduces 16-bit/565 banding on wall-tablet gradients.
        window.setFormat(PixelFormat.RGBA_8888)
        super.onCreate(savedInstanceState)
        window.setFormat(PixelFormat.RGBA_8888)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        hideSystemUi()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideSystemUi()
    }

    /** Immersive sticky: no status bar / nav buttons on wall tablets. */
    private fun hideSystemUi() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.let { controller ->
                controller.hide(
                    WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars(),
                )
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                )
        }
    }

    override fun onDestroy() {
        stopSensors()
        doorbellRinger?.stop()
        doorbellRinger = null
        apkInstaller?.dispose()
        apkInstaller = null
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
        }
        wakeLock = null
        super.onDestroy()
    }
}
