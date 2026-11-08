// MediaFlow: keeps a Cover / Metadata Recovery running while the app is in the
// background or swiped away (a foreground service with a progress
// notification and Pause / Stop). Copied next to MainActivity.kt by
// tool/prepare_platforms.py; {{PACKAGE}} is the app's package.
package {{PACKAGE}}

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class BackgroundWorkService : Service() {
    companion object {
        const val CHANNEL_ID = "recovery_progress"
        const val NOTIFICATION_ID = 7401
        const val ENGINE_ID = "mediaflow_main"

        /** A job runs: the Flutter engine outlives the activity. */
        @Volatile var keepAlive = false
        @Volatile var activityAlive = false
        private var channel: MethodChannel? = null
        private var state: Map<String, Any?> = emptyMap()
        private var running: BackgroundWorkService? = null
        private val main = Handler(Looper.getMainLooper())

        /** A widget button / shortcut that opened the app ("log", "add", …). */
        @Volatile var pendingAction: String? = null

        fun takeIntent(intent: Intent?) {
            val a = intent?.getStringExtra("mediaflow_action") ?: return
            intent.removeExtra("mediaflow_action")
            pendingAction = a
            main.post { channel?.invokeMethod("launchAction", null) }
        }

        fun attach(context: Context, engine: FlutterEngine) {
            val app = context.applicationContext
            val ch = MethodChannel(engine.dartExecutor.binaryMessenger, "mediaflow/background")
            channel = ch
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "update" -> {
                        @Suppress("UNCHECKED_CAST")
                        state = (call.arguments as? Map<String, Any?>) ?: emptyMap()
                        keepAlive = true
                        val svc = running
                        if (svc != null) {
                            svc.show()
                            result.success(true)
                        } else {
                            try {
                                val i = Intent(app, BackgroundWorkService::class.java)
                                if (Build.VERSION.SDK_INT >= 26) app.startForegroundService(i) else app.startService(i)
                                result.success(true)
                            } catch (e: Exception) {
                                result.success(false) // not allowed right now (app in the background)
                            }
                        }
                    }
                    "stop" -> {
                        keepAlive = false
                        running?.let { it.stopForegroundCompat(); it.stopSelf() }
                        result.success(true)
                        // Nothing on screen and nothing to do: let the engine go.
                        if (!activityAlive) main.post {
                            if (!keepAlive && !activityAlive) {
                                FlutterEngineCache.getInstance().get(ENGINE_ID)?.destroy()
                                FlutterEngineCache.getInstance().remove(ENGINE_ID)
                            }
                        }
                    }
                    "takeAction" -> {
                        result.success(pendingAction)
                        pendingAction = null
                    }
                    "widget" -> {
                        @Suppress("UNCHECKED_CAST")
                        val data = (call.arguments as? Map<String, Any?>) ?: emptyMap()
                        val edit = app.getSharedPreferences(MediaFlowWidget.PREFS, Context.MODE_PRIVATE).edit()
                        for ((k, v) in data) edit.putString(k, v?.toString() ?: "")
                        edit.apply()
                        try { MediaFlowWidget.refreshAll(app) } catch (e: Exception) { }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        private fun send(action: String) = main.post { channel?.invokeMethod("action", action) }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = this
        if (Build.VERSION.SDK_INT >= 26) {
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Recovery progress", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Cover and Metadata Recovery running in the background"
                    setShowBadge(false)
                }
            )
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "pause", "resume", "stop" -> {
                send(intent.action!!)
                return START_NOT_STICKY
            }
        }
        val n = build()
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIFICATION_ID, n)
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        if (running === this) running = null
        super.onDestroy()
    }

    fun show() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, build())
    }

    @Suppress("DEPRECATION")
    fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= 24) stopForeground(Service.STOP_FOREGROUND_REMOVE) else stopForeground(true)
    }

    private fun action(name: String, code: Int): PendingIntent {
        val i = Intent(this, BackgroundWorkService::class.java).setAction(name)
        return PendingIntent.getService(this, code, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    @Suppress("DEPRECATION")
    private fun build(): Notification {
        val title = state["title"] as? String ?: "MediaFlow recovery"
        val text = state["text"] as? String ?: ""
        val done = (state["done"] as? Number)?.toInt() ?: 0
        val total = (state["total"] as? Number)?.toInt() ?: 0
        val paused = state["paused"] == true
        val presence = state["presence"] == true
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL_ID) else Notification.Builder(this)
        val open = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        b.setSmallIcon(applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
        if (!presence) {
            // A recovery: progress with Pause / Stop. (The Discord status
            // notification has neither: turn it off in Settings → Discord.)
            b.setProgress(if (total > 0) total else 0, done, total <= 0)
                .addAction(Notification.Action.Builder(0, if (paused) "Resume" else "Pause", action(if (paused) "resume" else "pause", 1)).build())
                .addAction(Notification.Action.Builder(0, "Stop", action("stop", 2)).build())
        }
        if (open != null) b.setContentIntent(open)
        if (Build.VERSION.SDK_INT >= 31) b.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        return b.build()
    }
}
