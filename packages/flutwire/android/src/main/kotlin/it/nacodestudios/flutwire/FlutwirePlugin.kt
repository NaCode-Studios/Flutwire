package it.nacodestudios.flutwire

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File

/**
 * The Android half of Flutwire: the notification in the shade, the permission to
 * post it, the app icon shortcut and the share sheet.
 *
 * It holds no policy. Dart decides what the notification says and when it
 * changes, and this class draws it and reports what the user did with it.
 */
class FlutwirePlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.NewIntentListener,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPermission: MethodChannel.Result? = null

    // The action that started the app, kept until Dart asks for it.
    private var launchAction: String? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        FlutwireBridge.detach()
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addOnNewIntentListener(this)
        binding.addRequestPermissionsResultListener(this)
        readAction(binding.activity.intent)?.let { launchAction = it }
    }

    override fun onDetachedFromActivityForConfigChanges() = detachActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addOnNewIntentListener(this)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() = detachActivity()

    private fun detachActivity() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    /** The app was already running and the user tapped the notification or the shortcut. */
    override fun onNewIntent(intent: Intent): Boolean {
        val action = readAction(intent) ?: return false
        if (!FlutwireBridge.deliver(action)) launchAction = action
        return true
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "initialize" -> initialize(call, result)
                "consumeAction" -> result.success(consumeAction())
                "permission" -> result.success(permissionState())
                "requestPermission" -> requestPermission(result)
                "showSummary" -> {
                    showSummary(call)
                    result.success(null)
                }
                "cancelSummary" -> {
                    NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
                    result.success(null)
                }
                "openNotificationSettings" -> {
                    openNotificationSettings()
                    result.success(null)
                }
                "share" -> result.success(share(call))
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("flutwire", error.message, null)
        }
    }

    private fun initialize(call: MethodCall, result: MethodChannel.Result) {
        val name = call.argument<String>("channelName") ?: "Network activity"
        val description = call.argument<String>("channelDescription") ?: ""
        NotificationManagerCompat.from(context).createNotificationChannel(
            NotificationChannelCompat.Builder(CHANNEL_ID, NotificationManagerCompat.IMPORTANCE_LOW)
                .setName(name)
                .setDescription(description)
                .setShowBadge(false)
                .build(),
        )
        call.argument<String>("shortcutLabel")?.let { pushShortcut(it) }
        FlutwireBridge.attach { action -> channel.invokeMethod("onAction", action) }
        val temporary = File(context.cacheDir, "flutwire").apply { mkdirs() }
        result.success(
            mapOf(
                "permission" to permissionState(),
                // Not backed up: the history can hold tokens.
                "storagePath" to context.noBackupFilesDir.path,
                "temporaryPath" to temporary.path,
            ),
        )
    }

    /** Returns the pending action once: the one that launched the app, or one saved by the receiver. */
    private fun consumeAction(): String? {
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val saved = preferences.getString(KEY_PENDING, null)
        if (saved != null) preferences.edit().remove(KEY_PENDING).apply()
        val action = launchAction ?: saved
        launchAction = null
        return action
    }

    private fun permissionState(): String {
        if (Build.VERSION.SDK_INT >= 33) {
            val granted = ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
            if (!granted) {
                // Before the first request Android also answers "not granted"; only
                // a refusal that asked not to be asked again is final.
                val asked = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                    .getBoolean(KEY_ASKED, false)
                return if (asked) "denied" else "notDetermined"
            }
        }
        return if (NotificationManagerCompat.from(context).areNotificationsEnabled()) {
            "granted"
        } else {
            "denied"
        }
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (permissionState() == "granted") return result.success("granted")
        val host = activity
        if (Build.VERSION.SDK_INT < 33 || host == null) return result.success(permissionState())
        pendingPermission?.success("denied")
        pendingPermission = result
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_ASKED, true).apply()
        ActivityCompat.requestPermissions(
            host,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_PERMISSION,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_PERMISSION) return false
        pendingPermission?.success(permissionState())
        pendingPermission = null
        return true
    }

    @SuppressLint("MissingPermission")
    private fun showSummary(call: MethodCall) {
        val manager = NotificationManagerCompat.from(context)
        if (!manager.areNotificationsEnabled()) return
        val title = call.argument<String>("title") ?: ""
        val lines = call.argument<List<String>>("lines") ?: emptyList()
        val summary = call.argument<String>("summary") ?: ""
        val count = call.argument<Int>("count") ?: lines.size
        val clearLabel = call.argument<String>("clearLabel") ?: "Clear"

        val inbox = NotificationCompat.InboxStyle()
            .setBigContentTitle(title)
            .setSummaryText(summary)
        lines.forEach { inbox.addLine(it) }

        val clear = PendingIntent.getBroadcast(
            context,
            REQUEST_CLEAR,
            Intent(context, FlutwireReceiver::class.java).setAction(ACTION_CLEAR),
            PENDING_FLAGS,
        )

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.flutwire_ic_notification)
            .setContentTitle(title)
            .setContentText(lines.firstOrNull() ?: summary)
            .setSubText(summary)
            .setStyle(inbox)
            .setNumber(count)
            .setColor(ACCENT_COLOR)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setOnlyAlertOnce(true)
            .setAutoCancel(false)
            .setLocalOnly(true)
            .setShowWhen(false)
            .addAction(0, clearLabel, clear)

        val open = openIntent()
        if (open != null) {
            builder.setContentIntent(
                PendingIntent.getActivity(context, REQUEST_OPEN, open, PENDING_FLAGS),
            )
        }

        try {
            manager.notify(NOTIFICATION_ID, builder.build())
        } catch (_: SecurityException) {
            // Permission was withdrawn between the check and the call.
        }
    }

    /** The intent that brings the app forward and tells it to open the inspector. */
    private fun openIntent(): Intent? {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: return null
        return Intent(launch).apply {
            action = ACTION_OPEN
            putExtra(EXTRA_ACTION, "open")
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
        }
    }

    private fun pushShortcut(label: String) {
        val intent = openIntent() ?: return
        val shortcut = ShortcutInfoCompat.Builder(context, SHORTCUT_ID)
            .setShortLabel(label)
            .setLongLabel(label)
            .setIcon(IconCompat.createWithResource(context, R.drawable.flutwire_ic_shortcut))
            .setIntent(intent)
            .build()
        ShortcutManagerCompat.pushDynamicShortcut(context, shortcut)
    }

    private fun openNotificationSettings() {
        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    private fun share(call: MethodCall): Boolean {
        val text = call.argument<String>("text")
        val path = call.argument<String>("filePath")
        val mime = call.argument<String>("mimeType") ?: "text/plain"
        val subject = call.argument<String>("subject")
        if (text == null && path == null) return false

        val send = Intent(Intent.ACTION_SEND).apply {
            type = mime
            if (text != null) putExtra(Intent.EXTRA_TEXT, text)
            if (subject != null) putExtra(Intent.EXTRA_SUBJECT, subject)
            if (path != null) {
                val uri = FileProvider.getUriForFile(
                    context,
                    "${context.packageName}.flutwire.fileprovider",
                    File(path),
                )
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        }
        val chooser = Intent.createChooser(send, null)
        val host = activity
        if (host != null) {
            host.startActivity(chooser)
        } else {
            context.startActivity(chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
        return true
    }

    private fun readAction(intent: Intent?): String? {
        val action = intent?.getStringExtra(EXTRA_ACTION) ?: return null
        // Consumed: a rotation must not open the inspector a second time.
        intent.removeExtra(EXTRA_ACTION)
        return action
    }

    companion object {
        private const val CHANNEL = "it.nacodestudios.flutwire/native"
        private const val CHANNEL_ID = "it.nacodestudios.flutwire.network"
        private const val SHORTCUT_ID = "it.nacodestudios.flutwire.open"
        private const val PREFERENCES = "it.nacodestudios.flutwire"
        private const val KEY_PENDING = "pending"
        private const val KEY_ASKED = "asked"
        private const val EXTRA_ACTION = "it.nacodestudios.flutwire.ACTION"
        private const val REQUEST_OPEN = 1
        private const val REQUEST_CLEAR = 2
        private const val REQUEST_PERMISSION = 8731
        private const val ACCENT_COLOR = 0xFFF0803A.toInt()
        private const val PENDING_FLAGS =
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT

        const val ACTION_OPEN = "it.nacodestudios.flutwire.OPEN"
        const val ACTION_CLEAR = "it.nacodestudios.flutwire.CLEAR"
        const val NOTIFICATION_ID = 1138

        /** Keeps [action] for the next time Dart starts. */
        fun remember(context: Context, action: String) {
            context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                .edit().putString(KEY_PENDING, action).apply()
        }
    }
}
