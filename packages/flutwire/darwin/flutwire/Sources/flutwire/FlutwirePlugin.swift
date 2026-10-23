#if os(iOS)
import Flutter
import UIKit
#elseif os(macOS)
import FlutterMacOS
import AppKit
#endif
import UserNotifications

/// The Apple half of Flutwire, shared by iOS and macOS: the notification, the
/// permission to post it, and the share sheet.
///
/// It holds no policy. Dart decides what the notification says and when it
/// changes; this class draws it and reports what the user did with it.
///
/// The app may already have a notification delegate, for push or for its own
/// local notifications. Flutwire takes the delegate over and passes everything
/// that is not its own notification on to the one it replaced, so neither side
/// notices the other.
public final class FlutwirePlugin: NSObject, FlutterPlugin, UNUserNotificationCenterDelegate {
    private static let channelName = "it.nacodestudios.flutwire/native"
    private static let notificationId = "it.nacodestudios.flutwire.summary"
    private static let categoryId = "it.nacodestudios.flutwire.category"
    private static let clearActionId = "it.nacodestudios.flutwire.clear"
    private static let threadId = "it.nacodestudios.flutwire"
    private static let pendingKey = "it.nacodestudios.flutwire.pending"
    private static let askedKey = "it.nacodestudios.flutwire.asked"

    // The registrar does not keep a plugin alive and the notification center
    // holds its delegate weakly, so the instance is held here.
    private static var shared: FlutwirePlugin?

    private let channel: FlutterMethodChannel
    private weak var previousDelegate: UNUserNotificationCenterDelegate?
    private var dartIsListening = false
    private var launchAction: String?

    private init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        #if os(iOS)
        let messenger = registrar.messenger()
        #else
        let messenger = registrar.messenger
        #endif
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
        let instance = FlutwirePlugin(channel: channel)
        shared = instance
        registrar.addMethodCallDelegate(instance, channel: channel)
        instance.adoptNotificationCenter()
    }

    // MARK: Method calls

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "initialize":
            initialize(arguments, result: result)
        case "consumeAction":
            result(consumeAction())
        case "permission":
            permissionState { result($0) }
        case "requestPermission":
            requestPermission(result: result)
        case "showSummary":
            showSummary(arguments)
            result(nil)
        case "cancelSummary":
            let center = UNUserNotificationCenter.current()
            center.removeDeliveredNotifications(withIdentifiers: [Self.notificationId])
            center.removePendingNotificationRequests(withIdentifiers: [Self.notificationId])
            result(nil)
        case "openNotificationSettings":
            openNotificationSettings()
            result(nil)
        case "share":
            result(share(arguments))
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func initialize(_ arguments: [String: Any], result: @escaping FlutterResult) {
        adoptNotificationCenter()
        registerCategory(clearLabel: arguments["clearLabel"] as? String ?? "Clear")
        dartIsListening = true
        let storage = Self.storageDirectory()
        let temporary = Self.temporaryDirectory()
        permissionState { permission in
            result([
                "permission": permission,
                "storagePath": storage as Any,
                "temporaryPath": temporary as Any,
            ])
        }
    }

    // MARK: Notification center

    /// Becomes the notification delegate, keeping the one that was there.
    /// It runs at registration and again when Dart starts, because an app may
    /// set its own delegate after plugins register.
    private func adoptNotificationCenter() {
        let center = UNUserNotificationCenter.current()
        guard center.delegate !== self else { return }
        previousDelegate = center.delegate
        center.delegate = self
    }

    private func registerCategory(clearLabel: String) {
        let center = UNUserNotificationCenter.current()
        // Not foreground: clearing must not pull the app to the front.
        let clear = UNNotificationAction(identifier: Self.clearActionId, title: clearLabel, options: [])
        let category = UNNotificationCategory(
            identifier: Self.categoryId,
            actions: [clear],
            intentIdentifiers: [],
            options: []
        )
        center.getNotificationCategories { existing in
            var categories = existing.filter { $0.identifier != Self.categoryId }
            categories.insert(category)
            center.setNotificationCategories(categories)
        }
    }

    private func showSummary(_ arguments: [String: Any]) {
        let content = UNMutableNotificationContent()
        content.title = arguments["title"] as? String ?? ""
        content.subtitle = arguments["summary"] as? String ?? ""
        let lines = arguments["lines"] as? [String] ?? []
        content.body = lines.joined(separator: "\n")
        content.threadIdentifier = Self.threadId
        content.categoryIdentifier = Self.categoryId
        // Passive: it joins the list quietly, with no banner, no sound and no
        // wake of the screen, however often it is updated.
        if #available(iOS 15.0, macOS 12.0, *) {
            content.interruptionLevel = .passive
        }
        let request = UNNotificationRequest(identifier: Self.notificationId, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func permissionState(_ done: @escaping (String) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let state: String
            switch settings.authorizationStatus {
            case .notDetermined: state = "notDetermined"
            case .denied: state = "denied"
            default: state = "granted"
            }
            DispatchQueue.main.async { done(state) }
        }
    }

    private func requestPermission(result: @escaping FlutterResult) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
            DispatchQueue.main.async { result(granted ? "granted" : "denied") }
        }
    }

    // MARK: Delegate

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if notification.request.identifier == Self.notificationId {
            // The app is in front, so the inspector is a tap away: keep the
            // summary in the list and never interrupt with a banner.
            completionHandler([.list])
            return
        }
        if let previous = previousDelegate,
           previous.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:))) {
            previous.userNotificationCenter?(center, willPresent: notification, withCompletionHandler: completionHandler)
        } else {
            completionHandler([])
        }
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.notification.request.identifier == Self.notificationId else {
            if let previous = previousDelegate,
               previous.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:))) {
                previous.userNotificationCenter?(center, didReceive: response, withCompletionHandler: completionHandler)
            } else {
                completionHandler()
            }
            return
        }
        switch response.actionIdentifier {
        case Self.clearActionId:
            center.removeDeliveredNotifications(withIdentifiers: [Self.notificationId])
            deliver("clear")
        case UNNotificationDefaultActionIdentifier:
            deliver("open")
        default:
            break
        }
        completionHandler()
    }

    // MARK: Actions

    /// Hands an action to Dart, or keeps it for when Dart asks.
    private func deliver(_ action: String) {
        if dartIsListening {
            DispatchQueue.main.async { self.channel.invokeMethod("onAction", arguments: action) }
        } else if action == "clear" {
            // A launch that only carried Clear never reaches Dart, so it waits
            // on disk for the next start.
            UserDefaults.standard.set(action, forKey: Self.pendingKey)
        } else {
            launchAction = action
        }
    }

    private func consumeAction() -> String? {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: Self.pendingKey)
        if saved != nil { defaults.removeObject(forKey: Self.pendingKey) }
        let action = launchAction ?? saved
        launchAction = nil
        return action
    }

    // MARK: Files and sharing

    private static func storageDirectory() -> String? {
        let manager = FileManager.default
        guard let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        var folder = support.appendingPathComponent("flutwire", isDirectory: true)
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        // Not backed up: the history can hold tokens.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        return support.path
    }

    private static func temporaryDirectory() -> String? {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("flutwire", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.path
    }

    private func openNotificationSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #else
        let modern = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        let legacy = URL(string: "x-apple.systempreferences:com.apple.preference.notifications")
        if let modern = modern, NSWorkspace.shared.open(modern) { return }
        if let legacy = legacy { NSWorkspace.shared.open(legacy) }
        #endif
    }

    private func share(_ arguments: [String: Any]) -> Bool {
        var items: [Any] = []
        if let text = arguments["text"] as? String { items.append(text) }
        if let path = arguments["filePath"] as? String { items.append(URL(fileURLWithPath: path)) }
        if items.isEmpty { return false }
        let origin = arguments["origin"] as? [Double]

        #if os(iOS)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
        guard var presenter = window?.rootViewController else { return false }
        while let next = presenter.presentedViewController { presenter = next }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = presenter.view
            if let o = origin, o.count == 4 {
                popover.sourceRect = CGRect(x: o[0], y: o[1], width: o[2], height: o[3])
            } else {
                popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
        }
        presenter.present(sheet, animated: true)
        return true
        #else
        guard let view = NSApp.keyWindow?.contentView else { return false }
        var rect = NSRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        if let o = origin, o.count == 4 {
            rect = NSRect(x: o[0], y: view.bounds.height - o[1] - o[3], width: o[2], height: o[3])
        }
        NSSharingServicePicker(items: items).show(relativeTo: rect, of: view, preferredEdge: .minY)
        return true
        #endif
    }
}
