package com.example.archie_os

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Session-based APK install. ACTION_VIEW + FileProvider often ends in a generic
 * "App not installed" on wall tablets (URI grant / same versionCode).
 */
class ApkInstaller(private val activity: Activity) {
    private var pendingResult: MethodChannel.Result? = null
    private var receiver: BroadcastReceiver? = null

    fun install(path: String, result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("busy", "Installatie loopt al", null)
            return
        }

        val file = File(path)
        if (!file.exists() || file.length() < 1024L) {
            result.error("apk_missing", "APK ontbreekt of is te klein", null)
            return
        }
        if (!fileLooksLikeZip(file)) {
            result.error("apk_invalid", "Gedownload bestand is geen APK", null)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (!activity.packageManager.canRequestPackageInstalls()) {
                activity.startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:${activity.packageName}"),
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                result.error("install_permission_denied", "Installeren uit onbekende bronnen uit", null)
                return
            }
        }

        val incomingCode = archiveVersionCode(file)
        val installedCode = installedVersionCode()
        if (incomingCode != null && installedCode != null && incomingCode <= installedCode) {
            result.error(
                "apk_not_newer",
                "APK $incomingCode is niet nieuwer dan $installedCode",
                null,
            )
            return
        }

        pendingResult = result
        try {
            commitSession(file)
        } catch (e: Exception) {
            completeError("install_failed", e.message ?: "session")
        }
    }

    fun dispose() {
        if (pendingResult != null) {
            completeError("install_aborted", "activity gone")
        }
        unregisterReceiver()
        pendingResult = null
    }

    private fun commitSession(file: File) {
        val installer = activity.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(
            PackageInstaller.SessionParams.MODE_FULL_INSTALL,
        )
        params.setSize(file.length())
        if (Build.VERSION.SDK_INT >= 31) {
            params.setRequireUserAction(
                PackageInstaller.SessionParams.USER_ACTION_REQUIRED,
            )
        }
        val sessionId = installer.createSession(params)
        val session = installer.openSession(sessionId)
        try {
            session.openWrite("package", 0, file.length()).use { out ->
                file.inputStream().use { input ->
                    input.copyTo(out)
                }
                session.fsync(out)
            }
            registerReceiver()
            val pending = PendingIntent.getBroadcast(
                activity,
                sessionId,
                Intent(ACTION).setPackage(activity.packageName),
                pendingFlags(),
            )
            session.commit(pending.intentSender)
        } catch (e: Exception) {
            try {
                session.abandon()
            } catch (_: Exception) {
            }
            throw e
        } finally {
            try {
                session.close()
            } catch (_: Exception) {
            }
        }
    }

    private fun registerReceiver() {
        unregisterReceiver()
        val r = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                handleStatus(intent)
            }
        }
        receiver = r
        val filter = IntentFilter(ACTION)
        if (Build.VERSION.SDK_INT >= 33) {
            activity.registerReceiver(r, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            activity.registerReceiver(r, filter)
        }
    }

    private fun unregisterReceiver() {
        val r = receiver ?: return
        try {
            activity.unregisterReceiver(r)
        } catch (_: Exception) {
        }
        receiver = null
    }

    private fun handleStatus(intent: Intent?) {
        if (intent == null) return
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirm = if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                if (confirm != null) {
                    confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    activity.startActivity(confirm)
                }
            }
            PackageInstaller.STATUS_SUCCESS -> completeOk()
            else -> completeError(statusCode(status), message ?: "status $status")
        }
    }

    private fun completeOk() {
        val r = pendingResult
        pendingResult = null
        unregisterReceiver()
        r?.success(true)
    }

    private fun completeError(code: String, message: String) {
        val r = pendingResult
        pendingResult = null
        unregisterReceiver()
        r?.error(code, message, null)
    }

    private fun archiveVersionCode(file: File): Long? {
        val info = activity.packageManager.getPackageArchiveInfo(file.absolutePath, 0)
            ?: return null
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
    }

    private fun installedVersionCode(): Long? {
        return try {
            val p = activity.packageManager.getPackageInfo(activity.packageName, 0)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                p.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                p.versionCode.toLong()
            }
        } catch (_: PackageManager.NameNotFoundException) {
            null
        }
    }

    private fun pendingFlags(): Int {
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= 31) {
            flags = flags or PendingIntent.FLAG_MUTABLE
        }
        return flags
    }

    private fun fileLooksLikeZip(file: File): Boolean {
        file.inputStream().use { input ->
            val a = input.read()
            val b = input.read()
            return a == 0x50 && b == 0x4B
        }
    }

    private fun statusCode(status: Int): String = when (status) {
        PackageInstaller.STATUS_FAILURE_ABORTED -> "install_aborted"
        PackageInstaller.STATUS_FAILURE_BLOCKED -> "install_blocked"
        PackageInstaller.STATUS_FAILURE_CONFLICT -> "install_conflict"
        PackageInstaller.STATUS_FAILURE_INCOMPATIBLE -> "install_incompatible"
        PackageInstaller.STATUS_FAILURE_INVALID -> "apk_invalid"
        PackageInstaller.STATUS_FAILURE_STORAGE -> "install_storage"
        else -> "install_failed"
    }

    companion object {
        private const val ACTION = "com.example.archie_os.APK_INSTALL_STATUS"
    }
}
