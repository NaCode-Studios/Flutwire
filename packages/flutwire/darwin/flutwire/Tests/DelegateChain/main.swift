// A model of the notification delegates that sent the plugin into a loop, run against the real DelegateChain.
//
// A device is where these delegates meet, and CI has none. This models the three that did, each as its source
// behaves when a notification is tapped, and the notification center, which holds only one of them:
//
//   App        the app's own delegate. It completes the call, and it conforms to FlutterAppLifeCycleProvider,
//              so Firebase Messaging leaves it in place.
//   Messaging  firebase_messaging 16.6.0. It replaces a delegate that is not the app's, keeps it as the one to
//              pass on to, and passes every call on to that one.
//   Plugin     Flutwire. It handles its own notification and passes the rest on.
//
// The plugin runs twice, once as it passed calls on in 1.0.1, to a single remembered delegate, and once with
// DelegateChain, over the orders in which the three can take the center. The first has to loop where Firebase
// Messaging replaces the plugin between its two takes, or the model proves nothing. The second has to reach each
// delegate it should exactly once.
//
// From the root of the repository, on a Mac:
//
//   xcrun swiftc -swift-version 5 -o /tmp/delegate-chain \
//     packages/flutwire/darwin/flutwire/Sources/flutwire/DelegateChain.swift \
//     packages/flutwire/darwin/flutwire/Tests/DelegateChain/main.swift
//   /tmp/delegate-chain

import Foundation

@objc protocol Receiver: NSObjectProtocol {
    func receive(_ call: Call)
}

protocol LifecycleProvider {}

final class Call: NSObject {
    let own: Bool
    var log: [String] = []
    var completed = 0
    var looped = false

    init(own: Bool) {
        self.own = own
    }

    /// Records a delegate being reached. A real loop ends when the stack does, so the model gives up instead.
    func enter(_ name: String) -> Bool {
        log.append(name)
        if log.count > 100 { looped = true }
        return !looped
    }
}

/// The notification center: one weak delegate.
final class Center {
    weak var delegate: Receiver?

    func tap(own: Bool) -> Call {
        let call = Call(own: own)
        delegate?.receive(call)
        return call
    }
}

final class App: NSObject, Receiver, LifecycleProvider {
    func receive(_ call: Call) {
        _ = call.enter("App")
        call.completed += 1
    }
}

final class Messaging: NSObject, Receiver {
    private let name: String
    private var original: Receiver?

    init(name: String = "Messaging") {
        self.name = name
    }

    func configure(_ center: Center) {
        guard center.delegate !== self else { return }
        if let current = center.delegate {
            if current is LifecycleProvider { return }
            original = current
        }
        center.delegate = self
    }

    func receive(_ call: Call) {
        guard call.enter(name) else { return }
        if let original {
            original.receive(call)
        } else {
            call.completed += 1
        }
    }
}

protocol Plugin: Receiver {
    func takeTheCenter(_ center: Center)
}

/// The plugin as it was in 1.0.1: one remembered delegate.
final class SingleDelegate: NSObject, Plugin {
    private weak var previous: Receiver?

    func takeTheCenter(_ center: Center) {
        guard center.delegate !== self else { return }
        previous = center.delegate
        center.delegate = self
    }

    func receive(_ call: Call) {
        guard call.enter("Plugin") else { return }
        if call.own {
            call.completed += 1
        } else if let previous {
            previous.receive(call)
        } else {
            call.completed += 1
        }
    }
}

/// The plugin with the chain.
final class Chained: NSObject, Plugin {
    private let previous = DelegateChain<Receiver>()

    func takeTheCenter(_ center: Center) {
        guard center.delegate !== self else { return }
        if let current = center.delegate {
            previous.remember(current)
        }
        center.delegate = self
    }

    func receive(_ call: Call) {
        guard call.enter("Plugin") else { return }
        if call.own {
            call.completed += 1
            return
        }
        let passedOn = previous.forward(#selector(Receiver.receive(_:))) { $0.receive(call) }
        if !passedOn {
            call.completed += 1
        }
    }
}

struct Scenario {
    let name: String
    /// Whether the tap is on the plugin's own notification.
    let own: Bool
    /// The delegates that must each be reached once for the tap to count as passed on.
    let reaches: [String]
    /// Whether one remembered delegate loops in this order.
    let loopsWithOne: Bool
    /// Who takes the center, in order. The delegates are held in `keep`, because the center does not.
    let order: (Center, Plugin, inout [AnyObject]) -> Void
}

let scenarios: [Scenario] = [
    Scenario(
        name: "first launch of a build: the app, then the plugin when Dart starts",
        own: false, reaches: ["App"], loopsWithOne: false
    ) { center, plugin, keep in
        let app = App(), messaging = Messaging()
        keep += [app, messaging]
        center.delegate = app
        messaging.configure(center)
        plugin.takeTheCenter(center)
    },
    Scenario(
        name: "later launch: the plugin takes the center at registration, Firebase Messaging replaces it, "
            + "the plugin takes it again when Dart starts",
        own: false, reaches: ["Messaging", "App"], loopsWithOne: true
    ) { center, plugin, keep in
        let app = App(), messaging = Messaging()
        keep += [app, messaging]
        center.delegate = app
        plugin.takeTheCenter(center)
        messaging.configure(center)
        plugin.takeTheCenter(center)
    },
    Scenario(
        name: "the same order, a tap on the plugin's own notification",
        own: true, reaches: ["Plugin"], loopsWithOne: false
    ) { center, plugin, keep in
        let app = App(), messaging = Messaging()
        keep += [app, messaging]
        center.delegate = app
        plugin.takeTheCenter(center)
        messaging.configure(center)
        plugin.takeTheCenter(center)
    },
    Scenario(
        name: "the app sets its delegate after the plugins register",
        own: false, reaches: ["App"], loopsWithOne: false
    ) { center, plugin, keep in
        let app = App(), messaging = Messaging()
        keep += [app, messaging]
        plugin.takeTheCenter(center)
        center.delegate = app
        messaging.configure(center)
        plugin.takeTheCenter(center)
    },
    Scenario(
        name: "the same order, a tap on the plugin's own notification",
        own: true, reaches: ["Plugin"], loopsWithOne: false
    ) { center, plugin, keep in
        let app = App(), messaging = Messaging()
        keep += [app, messaging]
        plugin.takeTheCenter(center)
        center.delegate = app
        messaging.configure(center)
        plugin.takeTheCenter(center)
    },
    Scenario(
        name: "Firebase Messaging first, the plugin after",
        own: false, reaches: ["Messaging"], loopsWithOne: false
    ) { center, plugin, keep in
        let messaging = Messaging()
        keep += [messaging]
        messaging.configure(center)
        plugin.takeTheCenter(center)
    },
    Scenario(
        name: "later launch, with a second plugin that keeps the delegate it replaces, on top of Firebase Messaging",
        own: false, reaches: ["Other", "Messaging", "App"], loopsWithOne: true
    ) { center, plugin, keep in
        let app = App(), messaging = Messaging(), other = Messaging(name: "Other")
        keep += [app, messaging, other]
        center.delegate = app
        plugin.takeTheCenter(center)
        messaging.configure(center)
        other.configure(center)
        plugin.takeTheCenter(center)
    },
]

func tap(_ scenario: Scenario, _ plugin: Plugin) -> Call {
    let center = Center()
    var keep: [AnyObject] = [plugin]
    scenario.order(center, plugin, &keep)
    return withExtendedLifetime(keep) { center.tap(own: scenario.own) }
}

var failures: [String] = []

for scenario in scenarios {
    let single = tap(scenario, SingleDelegate())
    if single.looped != scenario.loopsWithOne {
        let found = single.looped ? "loops" : "does not loop"
        failures.append("\(scenario.name): one remembered delegate \(found), and the model expects the opposite")
    }

    let chained = tap(scenario, Chained())
    let reachedOnce = scenario.reaches.allSatisfy { name in chained.log.filter { $0 == name }.count == 1 }
    if chained.looped || chained.completed != 1 || !reachedOnce {
        failures.append(
            "\(scenario.name): the chain went \(chained.log.joined(separator: " > ")) "
                + "and completed the tap \(chained.completed) times"
        )
    }
}

if failures.isEmpty {
    print("The chain reaches each delegate once in all \(scenarios.count) orders, and one remembered delegate loops where 1.0.1 did.")
} else {
    failures.forEach { print("FAIL: \($0)") }
    exit(1)
}
