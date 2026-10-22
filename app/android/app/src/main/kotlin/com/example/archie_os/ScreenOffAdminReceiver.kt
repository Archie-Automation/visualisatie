package com.example.archie_os

import android.app.admin.DeviceAdminReceiver

/** Alleen force-lock, zodat standby de backlight uit kan zetten. */
class ScreenOffAdminReceiver : DeviceAdminReceiver()
