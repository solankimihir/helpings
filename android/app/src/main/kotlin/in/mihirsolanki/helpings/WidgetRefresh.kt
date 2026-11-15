// `in` is a Kotlin keyword, so the package segment is escaped.
package `in`.mihirsolanki.helpings

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import java.time.LocalDate
import java.time.ZoneId

/**
 * Keeps the home-screen widgets on the right day without the app running.
 *
 * `updatePeriodMillis` alone isn't enough: Doze and many launchers delay
 * it for hours, and after a reboot the launcher redraws its cached views.
 * So each widget update arms an alarm for just after the next local
 * midnight, and [WidgetDayReceiver] also redraws after a reboot, an app
 * update, or a change to the clock or time zone.
 */
object WidgetRefresh {
    private val providers = listOf(
        HelpingsWidgetProvider::class.java,
        HelpingsMealsWidgetProvider::class.java,
    )

    /** Asks every placed widget to redraw from the saved data. */
    fun updateAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        for (provider in providers) {
            val ids = manager.getAppWidgetIds(ComponentName(context, provider))
            if (ids.isEmpty()) continue
            context.sendBroadcast(
                Intent(context, provider)
                    .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                    .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids),
            )
        }
    }

    /**
     * Arms (or re-arms) the alarm for 5 s past the next local midnight.
     * Inexact, so no exact-alarm permission is needed, but allowed while
     * idle so Doze can't hold it until morning.
     */
    fun scheduleNextMidnight(context: Context) {
        val zone = ZoneId.systemDefault()
        val at = LocalDate.now(zone).plusDays(1).atStartOfDay(zone)
            .toInstant().toEpochMilli() + 5_000
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        alarms.setAndAllowWhileIdle(AlarmManager.RTC, at, midnightIntent(context))
    }

    private fun midnightIntent(context: Context): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, WidgetDayReceiver::class.java).setAction(ACTION_NEW_DAY),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    const val ACTION_NEW_DAY = "in.mihirsolanki.helpings.WIDGET_NEW_DAY"
}

/** Midnight alarm, boot, app update, clock or time-zone change: redraw. */
class WidgetDayReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        WidgetRefresh.updateAll(context)
        WidgetRefresh.scheduleNextMidnight(context)
    }
}

/** True when the saved numbers are for today; otherwise widgets read as empty. */
fun SharedPreferences.isToday(): Boolean =
    getString("date", null) == LocalDate.now().toString()

/**
 * home_widget stores a Dart int with putInt or putLong depending on its
 * size, and getLong throws on an Int, so accept either.
 */
fun SharedPreferences.number(key: String): Long =
    (all[key] as? Number)?.toLong() ?: 0L

/** Opens the app with [link] (`helpings://today`, `helpings://add-meal`). */
fun launchApp(context: Context, link: String): PendingIntent =
    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(link))

fun plural(n: Long, one: String) = if (n == 1L) "1 $one" else "$n ${one}s"
