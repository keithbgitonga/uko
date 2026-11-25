package ke.uko.rider

import android.Manifest
import android.content.ContentUris
import android.content.pm.PackageManager
import android.provider.CalendarContract
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * On-device calendar bridge for rider suggestions.
 *
 * Reads the next 7 days of calendar instances that have a location and returns
 * at most 10 candidates (the Dart layer trims to 3). Calendar data never leaves
 * the device; only the selected destination/time is sent when the rider books.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "ke.uko.rider/calendar"
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSuggestions" -> {
                        if (hasCalendarPermission()) {
                            result.success(querySuggestions())
                        } else {
                            pendingResult = result
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.READ_CALENDAR),
                                CALENDAR_PERMISSION_REQUEST,
                            )
                        }
                    }
                    "hasPermission" -> result.success(hasCalendarPermission())
                    else -> result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != CALENDAR_PERMISSION_REQUEST) return
        val result = pendingResult
        pendingResult = null
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            result?.success(querySuggestions())
        } else {
            result?.success(mapOf("permission" to false, "suggestions" to emptyList<Map<String, Any>>()))
        }
    }

    private fun hasCalendarPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALENDAR) ==
            PackageManager.PERMISSION_GRANTED

    private fun querySuggestions(): Map<String, Any> {
        val now = System.currentTimeMillis()
        val end = now + 7L * 24 * 3600 * 1000
        val builder = CalendarContract.Instances.CONTENT_URI.buildUpon()
        ContentUris.appendId(builder, now)
        ContentUris.appendId(builder, end)

        val projection = arrayOf(
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.EVENT_LOCATION,
        )
        val suggestions = mutableListOf<Map<String, Any>>()
        val seen = mutableSetOf<String>()
        contentResolver.query(
            builder.build(),
            projection,
            null,
            null,
            CalendarContract.Instances.BEGIN + " ASC",
        )?.use { cursor ->
            while (cursor.moveToNext() && suggestions.size < 10) {
                val title = cursor.getString(0) ?: continue
                val location = cursor.getString(2)?.trim().orEmpty()
                if (location.isEmpty()) continue
                val begin = cursor.getLong(1)
                if (!seen.add("$title|$begin|$location")) continue
                suggestions.add(
                    mapOf(
                        "title" to title,
                        "startMillis" to begin,
                        "location" to location,
                    ),
                )
            }
        }
        return mapOf("permission" to true, "suggestions" to suggestions)
    }

    companion object {
        private const val CALENDAR_PERMISSION_REQUEST = 7011
    }
}
