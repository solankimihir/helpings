// `in` is a Kotlin keyword, so the package segment is escaped.
package `in`.mihirsolanki.helpings

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import java.text.NumberFormat
import java.util.Locale

/**
 * Home-screen widget: today's calories, and how many meals and foods
 * they came from. The app writes the numbers (lib/data/home_widget_data.dart);
 * numbers for a day that isn't today read as zero, so the widget starts
 * fresh after midnight (WidgetRefresh makes sure it redraws then).
 */
class HelpingsWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val isToday = widgetData.isToday()
        val calories = if (isToday) widgetData.number("calories") else 0L
        val meals = if (isToday) widgetData.number("meals") else 0L
        val items = if (isToday) widgetData.number("items") else 0L
        val incomplete = isToday && widgetData.getBoolean("incomplete", false)

        val kcal = NumberFormat.getIntegerInstance(Locale.US).format(calories) +
            if (incomplete) "+" else ""
        val mealsText = if (meals == 0L) {
            "Nothing logged yet"
        } else {
            "${plural(meals, "meal")} · ${plural(items, "item")}"
        }

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.helpings_widget).apply {
                setTextViewText(R.id.widget_calories, kcal)
                setTextViewText(R.id.widget_meals, mealsText)
                setViewVisibility(R.id.widget_note, if (incomplete) View.VISIBLE else View.GONE)
                setOnClickPendingIntent(R.id.widget_root, launchApp(context, "helpings://today"))
            }
            appWidgetManager.updateAppWidget(id, views)
        }
        WidgetRefresh.scheduleNextMidnight(context)
    }
}
