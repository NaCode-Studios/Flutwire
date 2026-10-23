package it.nacodestudios.flutwire

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationManagerCompat

/** Handles the Clear button of the notification. */
class FlutwireReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != FlutwirePlugin.ACTION_CLEAR) return
        NotificationManagerCompat.from(context).cancel(FlutwirePlugin.NOTIFICATION_ID)
        // If Dart is running it clears the history now. If not, the request waits
        // in the preferences and is carried out the next time the app starts.
        if (!FlutwireBridge.deliver("clear")) {
            FlutwirePlugin.remember(context, "clear")
        }
    }
}
