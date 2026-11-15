// `in` is a Kotlin keyword, so the package segment is escaped.
package `in`.mihirsolanki.helpings

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import androidx.core.widget.RemoteViewsCompat
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import java.text.NumberFormat
import java.util.Locale

/**
 * Home-screen widget: today's meals, each with its foods, in a scrolling
 * list. The app writes the rows pre-formatted as JSON under `lines`
 * (lib/data/home_widget_data.dart); rows saved for another day are ignored.
 */
class HelpingsMealsWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val isToday = widgetData.isToday()
        val calories = if (isToday) widgetData.number("calories") else 0L
        val incomplete = isToday && widgetData.getBoolean("incomplete", false)
        val total = NumberFormat.getIntegerInstance(Locale.US).format(calories) +
            (if (incomplete) "+" else "") + " kcal"
        val rows = if (isToday) rows(context, widgetData.getString("lines", null)) else emptyList()

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.helpings_meals_widget).apply {
                setTextViewText(R.id.meals_total, total)
                setOnClickPendingIntent(R.id.meals_root, launchApp(context, "helpings://today"))
                setOnClickPendingIntent(R.id.meals_add, launchApp(context, "helpings://add-meal"))
                setEmptyView(R.id.meals_list, R.id.meals_empty)
                setPendingIntentTemplate(R.id.meals_list, rowTapTemplate(context))
            }
            val items = RemoteViewsCompat.RemoteCollectionItems.Builder()
                .setHasStableIds(false)
                .setViewTypeCount(2)
            rows.forEachIndexed { i, row -> items.addItem(i.toLong(), row) }
            RemoteViewsCompat.setRemoteAdapter(
                context, views, id, R.id.meals_list, items.build(),
            )
            appWidgetManager.updateAppWidget(id, views)
        }
        WidgetRefresh.scheduleNextMidnight(context)
    }

    private fun rows(context: Context, json: String?): List<RemoteViews> {
        if (json.isNullOrEmpty()) return emptyList()
        val lines = try {
            JSONArray(json)
        } catch (e: Exception) {
            return emptyList()
        }
        val today = Intent().setData(Uri.parse("helpings://today"))
        return (0 until lines.length()).map { i ->
            val line = lines.getJSONObject(i)
            val header = line.optBoolean("h")
            val layout = if (header) R.layout.widget_meal_header else R.layout.widget_meal_item
            RemoteViews(context.packageName, layout).apply {
                setTextViewText(R.id.row_text, line.optString("t"))
                setTextViewText(R.id.row_kcal, line.optString("k"))
                setOnClickFillInIntent(R.id.row_root, today)
            }
        }
    }

    /**
     * Row taps fill their link into this. It has to be mutable for the
     * fill-in to apply; the component is explicit, so nothing else can
     * claim it.
     */
    private fun rowTapTemplate(context: Context): PendingIntent =
        PendingIntent.getActivity(
            context,
            1,
            Intent(context, MainActivity::class.java)
                .setAction(HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )
}
