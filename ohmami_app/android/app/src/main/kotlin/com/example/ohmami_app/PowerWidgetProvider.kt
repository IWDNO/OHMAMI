package com.example.ohmami_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import com.example.ohmami_app.R
import es.antonborri.home_widget.HomeWidgetBackgroundIntent

class PowerWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { updateWidget(context, manager, it) }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == AppWidgetManager.ACTION_APPWIDGET_UPDATE) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = intent.getIntArrayExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS) ?: intArrayOf()
            ids.forEach { updateWidget(context, manager, it) }
        }
    }

    private fun clickPI(context: Context, action: String, requestCode: Int): PendingIntent {
        return HomeWidgetBackgroundIntent.getBroadcast(
            context,
            Uri.parse("homewidget://POWER/$action")
        )
    }

    private fun updateWidget(context: Context, manager: AppWidgetManager, id: Int) {
        val views = RemoteViews(context.packageName, R.layout.widget_power)

        views.setOnClickPendingIntent(R.id.btn_sleep,     clickPI(context, "sleep", 1001))
        views.setOnClickPendingIntent(R.id.btn_hibernate, clickPI(context, "hibernate", 1002))
        views.setOnClickPendingIntent(R.id.btn_restart,   clickPI(context, "restart", 1003))
        views.setOnClickPendingIntent(R.id.btn_shutdown,  clickPI(context, "shutdown", 1004))

        manager.updateAppWidget(id, views)
    }
}