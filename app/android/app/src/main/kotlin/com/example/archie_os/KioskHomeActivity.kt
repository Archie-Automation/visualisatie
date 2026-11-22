package com.example.archie_os

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * Startscherm-alias. Blijft uit tot kioskmodus aan gaat.
 * Anders vraagt Android na een APK-update welk startscherm je wilt.
 */
class KioskHomeActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startActivity(
            Intent(this, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                )
            },
        )
        finish()
    }
}
