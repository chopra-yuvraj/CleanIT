package com.cleanit.cleanit

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)

            // Normal cleaning requests
            val normalChannel = NotificationChannel(
                "normal_requests",
                "Cleaning Requests",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications for new cleaning requests"
            }
            manager.createNotificationChannel(normalChannel)

            // Urgent requests with vibration
            val urgentChannel = NotificationChannel(
                "urgent_requests",
                "Urgent Requests",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Urgent cleaning requests that need immediate attention"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 200, 500)
            }
            manager.createNotificationChannel(urgentChannel)
        }
    }
}
