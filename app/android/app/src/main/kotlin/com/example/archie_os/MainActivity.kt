package com.example.archie_os

import android.annotation.SuppressLint
import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
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

private const val REQUEST_SCREEN_OFF_ADMIN = 4817

/**
 * Wandtablet wake:
 * - Proximity-sensor indien aanwezig
 * - Anders lichtsensor: snelle donkere dip = hand over sensor → wake
 * - [wakeScreen] ook aanroepbaar vanuit Flutter (alarm-inloop etc.)
 * - Standby (slaapkamer): [DevicePolicyManager.lockNow] zet de backlight uit.
 *   Een zwart vlak laat die aan.
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
    private var standbyCpuLock: PowerManager.WakeLock? = null
    private var inStandby = false
    private var standbyGeneration = 0
    private var standbyRelockCount = 0
    private var ignoreWakeUntilMs = 0L
    private var pendingAdminResult: MethodChannel.Result? = null
    private var screenOnReceiver: BroadcastReceiver? = null
    private var apkInstaller: ApkInstaller? = null
    private var doorbellRinger: DoorbellRinger? = null
    private var meldingAlertRinger: MeldingAlertRinger? = null

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
                "enterStandby" -> result.success(enterStandby())
                "leaveStandby" -> {
                    leaveStandby()
                    result.success(null)
                }
                "requestScreenOffAdmin" -> requestScreenOffAdmin(result)
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
                    val tone = call.argument<String>("tone") ?: "chime"
                    doorbellRinger?.start(volume, tone)
                    result.success(null)
                }
                "stop" -> {
                    doorbellRinger?.stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        meldingAlertRinger = MeldingAlertRinger(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "archie_os/melding_alert",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    meldingAlertRinger?.start()
                    result.success(null)
                }
                "stop" -> {
                    meldingAlertRinger?.stop()
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

    /** 0 = donkerst, BRIGHTNESS_OVERRIDE_NONE = systeemhelderheid. */
    private fun setWindowBrightness(value: Float) {
        val attrs = window.attributes
        attrs.screenBrightness = value
        window.attributes = attrs
    }

    private fun screenOffAdmin(): ComponentName =
        ComponentName(this, ScreenOffAdminReceiver::class.java)

    private fun isScreenOffAdminActive(): Boolean {
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        return dpm.isAdminActive(screenOffAdmin())
    }

    private fun requestScreenOffAdmin(result: MethodChannel.Result) {
        if (isScreenOffAdminActive()) {
            result.success(true)
            return
        }
        if (pendingAdminResult != null) {
            result.success(false)
            return
        }
        pendingAdminResult = result
        val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
            putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, screenOffAdmin())
            putExtra(
                DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                "Standby zet het scherm uit, inclusief de backlight, zodat een slaapkamer donker blijft. Daarvoor mag dit paneel het scherm vergrendelen. Niets anders.",
            )
        }
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, REQUEST_SCREEN_OFF_ADMIN)
        } catch (_: Exception) {
            pendingAdminResult = null
            result.success(false)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_SCREEN_OFF_ADMIN) return
        val pending = pendingAdminResult ?: return
        pendingAdminResult = null
        pending.success(isScreenOffAdminActive())
    }

    /**
     * Backlight uit. Een zwart Flutter-vlak is daar niet genoeg: de lcd blijft
     * gloeien zolang het paneel aan staat. lockNow() doet hetzelfde als de
     * aan/uit-knop. PARTIAL_WAKE_LOCK houdt de app wakker voor deurbel en sensor.
     */
    private fun enterStandby(): Boolean {
        if (!isScreenOffAdminActive()) {
            setWindowBrightness(0f)
            return false
        }
        val generation = ++standbyGeneration
        inStandby = true
        standbyRelockCount = 0
        // Scherm uit geeft zelf een lichtdip. Die mag niet meteen weer wekken.
        ignoreWakeUntilMs = System.currentTimeMillis() + 1200
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setWindowBrightness(0f)
        acquireStandbyCpuLock()
        return try {
            val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            dpm.lockNow()
            mainHandler.postDelayed({
                if (generation != standbyGeneration || !inStandby) return@postDelayed
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                if (!pm.isInteractive) return@postDelayed
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                try {
                    dpm.lockNow()
                } catch (_: SecurityException) {
                }
            }, 500)
            true
        } catch (_: Exception) {
            leaveStandby()
            false
        }
    }

    private fun leaveStandby() {
        standbyGeneration++
        inStandby = false
        standbyRelockCount = 0
        ignoreWakeUntilMs = 0L
        releaseStandbyCpuLock()
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setWindowBrightness(WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE)
    }

    @SuppressLint("WakelockTimeout")
    private fun acquireStandbyCpuLock() {
        if (standbyCpuLock == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            standbyCpuLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "archie_os:standby",
            ).apply { setReferenceCounted(false) }
        }
        val wl = standbyCpuLock ?: return
        if (!wl.isHeld) wl.acquire()
    }

    private fun releaseStandbyCpuLock() {
        try {
            standbyCpuLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
        }
    }

    private fun registerScreenOnReceiver() {
        if (screenOnReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action != Intent.ACTION_SCREEN_ON) return
                if (!inStandby || System.currentTimeMillis() < ignoreWakeUntilMs) return
                standbyGeneration++
                inStandby = false
                releaseStandbyCpuLock()
                bringScreenUp()
                try {
                    proximityEvents?.success("screenOn")
                } catch (_: Exception) {
                }
            }
        }
        screenOnReceiver = receiver
        val filter = IntentFilter(Intent.ACTION_SCREEN_ON)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }
    }

    private fun bringScreenUp() {
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
        setWindowBrightness(WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE)
    }

    private fun wakeScreen() {
        // Annuleer een lopende standby-herpoging (deurbel, alarm, sensor).
        val wasStandby = inStandby
        standbyGeneration++
        inStandby = false
        releaseStandbyCpuLock()
        val now = System.currentTimeMillis()
        // Short debounce — was 800ms and felt sluggish on wall panels.
        // Vanuit standby altijd doorzetten: het scherm staat dan echt uit.
        if (!wasStandby && now - lastWakeAtMs < 250) return
        lastWakeAtMs = now

        runOnUiThread {
            bringScreenUp()
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
        if (System.currentTimeMillis() < ignoreWakeUntilMs) return
        wakeScreen()
        mainHandler.post {
            try {
                proximityEvents?.success("near")
            } catch (_: Exception) {
            }
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
                    // Tijdens het uitzetten niet vastzetten op "near": anders
                    // wekt de eerstvolgende echte beweging niet meer.
                    if (System.currentTimeMillis() < ignoreWakeUntilMs) return
                    isNear = true
                    emitNear()
                } else if (!near) {
                    isNear = false
                }
            }
            Sensor.TYPE_LIGHT -> {
                val lux = event.values[0]
                // Backlight uit ziet eruit als een hand voor de sensor en zou
                // standby meteen weer opheffen. Aanraken of proximity wekt wel.
                if (inStandby || System.currentTimeMillis() < ignoreWakeUntilMs) {
                    lastLight = lux
                    return
                }
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
        registerScreenOnReceiver()
    }

    override fun onResume() {
        super.onResume()
        // Sommige panelen (zeker aan de lader) zetten het scherm meteen weer aan.
        if (!inStandby || System.currentTimeMillis() >= ignoreWakeUntilMs) return
        if (standbyRelockCount >= 3) return
        standbyRelockCount++
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        try {
            val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            dpm.lockNow()
        } catch (_: Exception) {
        }
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
        meldingAlertRinger?.stop()
        meldingAlertRinger = null
        apkInstaller?.dispose()
        apkInstaller = null
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
        }
        wakeLock = null
        releaseStandbyCpuLock()
        standbyCpuLock = null
        screenOnReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {
            }
        }
        screenOnReceiver = null
        pendingAdminResult?.success(false)
        pendingAdminResult = null
        super.onDestroy()
    }
}
