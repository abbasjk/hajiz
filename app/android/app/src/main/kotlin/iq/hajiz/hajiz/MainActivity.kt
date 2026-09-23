package iq.hajiz.hajiz

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // قناة "الحجوزات": صوت وظهور أعلى الشاشة، لأن مهلة الرد على الطلبات قصيرة
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel("bookings", "الحجوزات", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "طلبات الحجز والردود والتذكيرات"
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }
}
