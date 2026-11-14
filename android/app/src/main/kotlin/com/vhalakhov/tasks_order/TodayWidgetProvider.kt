package com.vhalakhov.tasks_order

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.util.Calendar
import java.util.Locale

/**
 * The home-screen widget with today's tasks (T-601, ADR-22).
 *
 * The app cannot be asked for the plan, so it leaves a cache of the coming
 * days (docs/03 Data Model.md, "Home-screen widget cache"); the widget picks
 * the current plan day itself. It is redrawn when the app sends a new cache,
 * at the next day start (an inexact alarm) and every 30 minutes by the
 * system. A tap anywhere opens the app.
 */
class TodayWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val views = render(context)
        for (id in ids) manager.updateAppWidget(id, views)
        scheduleDayStart(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_DAY_START) refresh(context) else super.onReceive(context, intent)
    }

    override fun onDisabled(context: Context) {
        alarmManager(context).cancel(dayStartIntent(context))
    }

    companion object {
        private const val PREFS = "today_widget"
        private const val KEY_CACHE = "cache"
        private const val ACTION_DAY_START = "com.vhalakhov.tasks_order.WIDGET_DAY_START"

        /** Stores the cache from the app and redraws the placed widgets. */
        fun save(context: Context, payload: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().putString(KEY_CACHE, payload).apply()
            refresh(context)
        }

        private fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, TodayWidgetProvider::class.java))
            if (ids.isEmpty()) return
            manager.updateAppWidget(ids, render(context))
            scheduleDayStart(context)
        }

        private fun cache(context: Context): JSONObject? = try {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(KEY_CACHE, null)?.let { JSONObject(it) }
        } catch (e: org.json.JSONException) {
            null
        }

        private fun dayStartHour(cache: JSONObject?): Int = cache?.optInt("dayStartHour", 0) ?: 0

        /** The plan day of [now] as `yyyy-MM-dd`: before the day start hour it is still yesterday (D15). */
        private fun planDate(now: Calendar, dayStartHour: Int): String {
            val day = now.clone() as Calendar
            if (day.get(Calendar.HOUR_OF_DAY) < dayStartHour) day.add(Calendar.DAY_OF_MONTH, -1)
            return String.format(
                Locale.ROOT, "%04d-%02d-%02d",
                day.get(Calendar.YEAR), day.get(Calendar.MONTH) + 1, day.get(Calendar.DAY_OF_MONTH),
            )
        }

        private fun render(context: Context): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_today)
            val cache = cache(context)
            val date = planDate(Calendar.getInstance(), dayStartHour(cache))
            val days = cache?.optJSONArray("days")
            val day = (0 until (days?.length() ?: 0))
                .map { days!!.getJSONObject(it) }
                .firstOrNull { it.optString("date") == date }

            if (day == null) {
                // No cache yet, or the app has not run for longer than the cached days.
                views.setTextViewText(R.id.widget_header, context.getString(R.string.widget_name))
                showText(
                    views,
                    cache?.optString("stale")?.takeIf { it.isNotEmpty() }
                        ?: context.getString(R.string.widget_open_app),
                    secondary = true,
                )
            } else {
                views.setTextViewText(R.id.widget_header, day.optString("header"))
                val lines = day.optJSONArray("lines")
                if (lines != null && lines.length() > 0) {
                    val text = (0 until lines.length()).joinToString("\n") { "•  " + lines.getString(it) }
                    showText(views, text, secondary = false)
                } else {
                    showText(views, day.optString("empty"), secondary = true)
                }
            }

            val open = Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            views.setOnClickPendingIntent(
                R.id.widget_root,
                PendingIntent.getActivity(
                    context, 0, open,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                ),
            )
            return views
        }

        private fun showText(views: RemoteViews, text: String, secondary: Boolean) {
            views.setTextViewText(R.id.widget_lines, if (secondary) "" else text)
            views.setViewVisibility(R.id.widget_lines, if (secondary) View.GONE else View.VISIBLE)
            views.setTextViewText(R.id.widget_empty, if (secondary) text else "")
            views.setViewVisibility(R.id.widget_empty, if (secondary) View.VISIBLE else View.GONE)
        }

        private fun alarmManager(context: Context) =
            context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        private fun dayStartIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
            context, 0,
            Intent(context, TodayWidgetProvider::class.java).setAction(ACTION_DAY_START),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        /** An inexact alarm at the next day start, a minute after it; needs no permission. */
        private fun scheduleDayStart(context: Context) {
            val hour = dayStartHour(cache(context))
            val next = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, 1)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            if (!next.after(Calendar.getInstance())) next.add(Calendar.DAY_OF_MONTH, 1)
            alarmManager(context).set(AlarmManager.RTC, next.timeInMillis, dayStartIntent(context))
        }
    }
}
