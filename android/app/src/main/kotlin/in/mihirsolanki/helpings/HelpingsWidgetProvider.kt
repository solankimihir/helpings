// `in` is a Kotlin keyword, so the package segment is escaped.
package `in`.mihirsolanki.helpings

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.text.NumberFormat
import java.time.LocalDate
import java.util.Locale

/**
 * Home-screen widget: today's calories and meal count, and an Add meal
 * button. The app writes the numbers (lib/data/home_widget_data.dart);
 * numbers for a day that isn't today read as zero, so the widget starts
 * fresh after midnight.
 */
class HelpingsWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val isToday = widgetData.getString("date", null) == LocalDate.now().toString()
        val calories = if (isToday) widgetData.number("calories") else 0L
        val meals = if (isToday) widgetData.number("meals") else 0L
        val incomplete = isToday && widgetData.getBoolean("incomplete", false)

        val kcal = NumberFormat.getIntegerInstance(Locale.US).format(calories) +
            if (incomplete) "+" else ""
        val mealsText = when {
            meals == 0L -> "Nothing logged yet"
            incomplete -> "${plural(meals, "meal")} · some without calories"
            else -> plural(meals, "meal")
        }

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.helpings_widget).apply {
                setTextViewText(R.id.widget_calories, kcal)
                setTextViewText(R.id.widget_meals, mealsText)
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(
                        context, MainActivity::class.java, Uri.parse("helpings://today"),
                    ),
                )
                setOnClickPendingIntent(
                    R.id.widget_add,
                    HomeWidgetLaunchIntent.getActivity(
                        context, MainActivity::class.java, Uri.parse("helpings://add-meal"),
                    ),
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    /**
     * home_widget stores a Dart int with putInt or putLong depending on its
     * size, and getLong throws on an Int, so accept either.
     */
    private fun SharedPreferences.number(key: String): Long =
        (all[key] as? Number)?.toLong() ?: 0L

    private fun plural(n: Long, one: String) = if (n == 1L) "1 $one" else "$n ${one}s"
}
