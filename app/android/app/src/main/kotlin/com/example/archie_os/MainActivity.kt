package com.example.archie_os

import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.provider.Settings
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

private const val PREFS_BRIGHTNESS = "archie_standby_brightness"
private const val KEY_DIMMED = "dimmed"
private const val KEY_MODE = "mode"
private const val KEY_VALUE = "value"

/**
 * Wandtablet wake:
 * - Proximity-sensor indien aanwezig
 * - Anders lichtsensor: snelle donkere dip = hand over sensor → wake
 * - [wakeScreen] ook aanroepbaar vanuit Flutter (alarm-inloop etc.)
 * - Standby (slaapkamer): backlight naar 0, scherm blijft aanraakbaar.
 *   lockNow() zet op deze panelen ook het aanraakscherm uit.
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
    private var inStandby = false
    private var ignoreWakeUntilMs = 0L
    private var pendingBrightnessResult: MethodChannel.Result? = null
    private var awaitingWriteSettings = false
    private var screenOnReceiver: BroadcastReceiver? = null
    private var apkInstaller: ApkInstaller? = null
    private var doorbellRinger: DoorbellRinger? = null
    private var meldingAlertRinger: MeldingAlertRinger? = null
    private var alarmDelayRinger: AlarmDelayRinger? = null

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
                "canDimBrightness" -> result.success(canWriteSettings())
                "requestStandbyBrightness" -> requestStandbyBrightness(result)
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

        alarmDelayRinger = AlarmDelayRinger(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "archie_os/alarm_delay",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "play" -> {
                    val which = call.argument<String>("which") ?: "slow"
                    alarmDelayRinger?.play(which)
                    result.success(null)
                }
                "stop" -> {
                    alarmDelayRinger?.stop()
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

    private fun canWriteSettings(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.System.canWrite(this)
        } else {
            true
        }
    }

    /** Systeemscherm: helderheid wijzigen. Het aanraakscherm blijft daarbij aan. */
    private fun requestStandbyBrightness(result: MethodChannel.Result) {
        if (canWriteSettings()) {
            result.success(true)
            return
        }
        if (pendingBrightnessResult != null) {
            result.success(false)
            return
        }
        pendingBrightnessResult = result
        awaitingWriteSettings = true
        try {
            val intent = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
        } catch (_: Exception) {
            awaitingWriteSettings = false
            pendingBrightnessResult = null
            result.success(false)
        }
    }

    /**
     * Backlight uit, aanraking blijft werken.
     * lockNow() zet op deze panelen het digitizer uit; dan doet een vinger niets.
     */
    private fun enterStandby(): Boolean {
        inStandby = true
        // De lichtdip van het dimmen mag niet meteen als hand worden gezien.
        ignoreWakeUntilMs = System.currentTimeMillis() + 1500
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setWindowBrightness(0f)
        dimSystemBrightness()
        return true
    }

    private fun leaveStandby() {
        inStandby = false
        ignoreWakeUntilMs = 0L
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setWindowBrightness(WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE)
        restoreSystemBrightness()
    }

    private fun dimSystemBrightness() {
        if (!canWriteSettings()) return
        try {
            val prefs = brightnessPrefs()
            if (!prefs.getBoolean(KEY_DIMMED, false)) {
                val mode = Settings.System.getInt(
                    contentResolver,
                    Settings.System.SCREEN_BRIGHTNESS_MODE,
                    Settings.System.SCREEN_BRIGHTNESS_MODE_AUTOMATIC,
                )
                val value = Settings.System.getInt(
                    contentResolver,
                    Settings.System.SCREEN_BRIGHTNESS,
                    128,
                ).coerceIn(1, 255)
                prefs.edit()
                    .putInt(KEY_MODE, mode)
                    .putInt(KEY_VALUE, value)
                    .putBoolean(KEY_DIMMED, true)
                    .apply()
            }
            Settings.System.putInt(
                contentResolver,
                Settings.System.SCREEN_BRIGHTNESS_MODE,
                Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL,
            )
            Settings.System.putInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS, 0)
        } catch (_: Exception) {
        }
    }

    private fun restoreSystemBrightness() {
        val prefs = brightnessPrefs()
        if (!prefs.getBoolean(KEY_DIMMED, false)) return
        if (canWriteSettings()) {
            try {
                Settings.System.putInt(
                    contentResolver,
                    Settings.System.SCREEN_BRIGHTNESS,
                    prefs.getInt(KEY_VALUE, 128).coerceIn(1, 255),
                )
                Settings.System.putInt(
                    contentResolver,
                    Settings.System.SCREEN_BRIGHTNESS_MODE,
                    prefs.getInt(KEY_MODE, Settings.System.SCREEN_BRIGHTNESS_MODE_AUTOMATIC),
                )
            } catch (_: Exception) {
            }
        }
        prefs.edit().putBoolean(KEY_DIMMED, false).apply()
    }

    private fun brightnessPrefs() = getSharedPreferences(PREFS_BRIGHTNESS, MODE_PRIVATE)

    private fun registerScreenOnReceiver() {
        if (screenOnReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action != Intent.ACTION_SCREEN_ON) return
                if (!inStandby || System.currentTimeMillis() < ignoreWakeUntilMs) return
                inStandby = false
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
        restoreSystemBrightness()
    }

    private fun wakeScreen() {
        val wasStandby = inStandby
        inStandby = false
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
                // Dimmen geeft zelf een lichtdip. Daarna wekt een hand weer.
                if (System.currentTimeMillis() < ignoreWakeUntilMs) {
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
        // lockNow() maakte het aanraakscherm dood. Die beheerdersrol is niet meer nodig.
        releaseScreenOffAdmin()
        // Proces dood tijdens standby: niet vast op helderheid 0 opstarten.
        if (!inStandby) restoreSystemBrightness()
    }

    private fun releaseScreenOffAdmin() {
        try {
            val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            val who = ComponentName(this, ScreenOffAdminReceiver::class.java)
            if (dpm.isAdminActive(who)) dpm.removeActiveAdmin(who)
        } catch (_: Exception) {
        }
    }

    override fun onResume() {
        super.onResume()
        if (!awaitingWriteSettings) return
        awaitingWriteSettings = false
        val pending = pendingBrightnessResult ?: return
        pendingBrightnessResult = null
        pending.success(canWriteSettings())
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
        alarmDelayRinger?.stop()
        alarmDelayRinger = null
        apkInstaller?.dispose()
        apkInstaller = null
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
        }
        wakeLock = null
        restoreSystemBrightness()
        screenOnReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {
            }
        }
        screenOnReceiver = null
        pendingBrightnessResult?.success(false)
        pendingBrightnessResult = null
        awaitingWriteSettings = false
        super.onDestroy()
    }
}
