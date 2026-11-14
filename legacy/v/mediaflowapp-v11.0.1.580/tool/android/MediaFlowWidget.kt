// MediaFlow home-screen widget (Android): Day Streak, today's time, level and
// the title being logged, with a button that opens the Log page. The app
// writes the numbers (BackgroundWorkService "widget"); this only shows them.
// Copied next to MainActivity.kt by tool/prepare_platforms.py.
package {{PACKAGE}}

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class MediaFlowWidget : AppWidgetProvider() {
    companion object {
        const val PREFS = "mediaflow_widget"

        fun refreshAll(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(ComponentName(context, MediaFlowWidget::class.java))
            for (id in ids) mgr.updateAppWidget(id, views(context))
        }

        private fun open(context: Context, action: String, code: Int): PendingIntent? {
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return null
            launch.putExtra("mediaflow_action", action)
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            return PendingIntent.getActivity(context, code, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        private fun views(context: Context): RemoteViews {
            val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val v = RemoteViews(context.packageName, R.layout.mediaflow_widget)
            v.setTextViewText(R.id.mf_streak, p.getString("streak", "—"))
            v.setTextViewText(R.id.mf_today, p.getString("today", "Open MediaFlow to load your account"))
            v.setTextViewText(R.id.mf_title, p.getString("title", ""))
            v.setTextViewText(R.id.mf_progress, p.getString("progress", ""))
            open(context, "open", 10)?.let { v.setOnClickPendingIntent(R.id.mf_root, it) }
            open(context, "log", 11)?.let { v.setOnClickPendingIntent(R.id.mf_log, it) }
            open(context, "add", 12)?.let { v.setOnClickPendingIntent(R.id.mf_add, it) }
            return v
        }
    }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, views(context))
    }
}
