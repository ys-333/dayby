package com.yashwantsingh.riyaz

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONObject

/**
 * Home-screen widget showing today's commitments.
 *
 * Draws only what Dart hands it. Every string here was decided by the
 * accounting engine — this class does no arithmetic and knows nothing about
 * skips, pauses or period targets, because a second implementation of those
 * rules would eventually disagree with the first.
 *
 * Classic RemoteViews rather than Jetpack Glance: Glance needs Compose on the
 * Gradle classpath, and this widget is a heading and a handful of rows. The
 * spec asked for Glance, but it predates the Flutter decision.
 */
class RiyazWidgetProvider : AppWidgetProvider() {

    companion object {
        const val PREFS = "riyaz.widget"
        const val KEY_PAYLOAD = "payload"

        /** Row slots in the layout. A widget has no list view without a
         *  RemoteViewsService, and five rows covers the common case. */
        private val ROW_IDS = intArrayOf(
            R.id.row_0, R.id.row_1, R.id.row_2, R.id.row_3, R.id.row_4
        )

        /** Redraws every placed instance. Called after Dart pushes new data. */
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, RiyazWidgetProvider::class.java)
            )
            for (id in ids) render(context, manager, id)
        }

        private fun render(context: Context, manager: AppWidgetManager, id: Int) {
            val views = RemoteViews(context.packageName, R.layout.riyaz_widget)
            val raw = context
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(KEY_PAYLOAD, null)

            if (raw == null) {
                // Never seen data: say so plainly rather than showing an empty
                // frame the user cannot interpret.
                views.setTextViewText(R.id.date_label, "Riyaz")
                views.setTextViewText(R.id.progress_label, "")
                views.setTextViewText(R.id.row_0, "Open the app to get started")
                for (i in 1 until ROW_IDS.size) {
                    views.setTextViewText(ROW_IDS[i], "")
                }
            } else {
                applyPayload(views, raw)
            }

            // Whole widget opens the app. Completing directly from the widget
            // would need a background Dart isolate to run the accounting
            // engine; the spec explicitly allows deep-linking instead.
            val launch = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
                ?.apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP }
            if (launch != null) {
                views.setOnClickPendingIntent(
                    R.id.widget_root,
                    PendingIntent.getActivity(
                        context, 0, launch,
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                    )
                )
            }

            manager.updateAppWidget(id, views)
        }

        private fun applyPayload(views: RemoteViews, raw: String) {
            try {
                val json = JSONObject(raw)
                views.setTextViewText(R.id.date_label, json.optString("dateLabel"))
                views.setTextViewText(R.id.progress_label, json.optString("progressLabel"))

                if (json.optBoolean("isEmpty", false)) {
                    // Dart decides the wording: "nothing tracked" and "nothing
                    // due today" are different facts, and telling them apart
                    // needs the accounting rules this class deliberately lacks.
                    views.setTextViewText(
                        R.id.row_0,
                        json.optString("emptyLabel", "Nothing to track yet")
                    )
                    for (i in 1 until ROW_IDS.size) {
                        views.setTextViewText(ROW_IDS[i], "")
                    }
                    return
                }

                val rows = json.optJSONArray("rows")
                for (i in ROW_IDS.indices) {
                    val text = if (rows != null && i < rows.length()) {
                        val row = rows.getJSONObject(i)
                        val detail = row.optString("detail")
                        buildString {
                            append(row.optString("label"))
                            append("  ")
                            append(if (detail.isNotEmpty()) detail else row.optString("glyph"))
                        }
                    } else {
                        ""
                    }
                    views.setTextViewText(ROW_IDS[i], text)
                }

                // More commitments than slots: say how many are hidden rather
                // than silently truncating the list.
                val total = rows?.length() ?: 0
                if (total > ROW_IDS.size) {
                    views.setTextViewText(
                        ROW_IDS[ROW_IDS.size - 1],
                        "+${total - ROW_IDS.size + 1} more"
                    )
                }
            } catch (e: Exception) {
                // A malformed payload must not leave a crashed widget on the
                // home screen; show something honest instead.
                views.setTextViewText(R.id.date_label, "Riyaz")
                views.setTextViewText(R.id.row_0, "Open the app to refresh")
            }
        }
    }

    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) render(context, manager, id)
    }
}
