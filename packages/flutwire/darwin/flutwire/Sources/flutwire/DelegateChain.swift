import Foundation

/// The delegates a plugin has taken a single-delegate object from, newest first, and the order in which a call
/// is handed to them.
///
/// A plugin that takes a delegate over passes on whatever is not its own to the one it replaced. A second plugin
/// that does the same afterwards, as Firebase Messaging does, keeps the first as the delegate it passes on to.
/// If the first then takes the delegate back, the one it remembers is the second, which hands every call
/// straight back, and with a single remembered delegate the two pass a call between them until the stack runs
/// out.
///
/// This keeps every delegate that was replaced. A call goes to the newest one that implements it and that the
/// call has not reached yet, so a delegate that hands the call back gets the next one down, and no delegate
/// gets the same call twice.
final class DelegateChain<Delegate: NSObjectProtocol> {
    private struct Entry {
        weak var delegate: Delegate?
    }

    /// The delegates the call being passed on, on this thread, has reached so far.
    private final class Reached {
        var delegates = Set<ObjectIdentifier>()
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private let threadKey = "it.nacodestudios.flutwire.chain.\(UUID().uuidString)"

    /// Makes [delegate] the newest one, whether or not it was here before.
    func remember(_ delegate: Delegate) {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll { entry in
            guard let known = entry.delegate else { return true }
            return identity(known) == identity(delegate)
        }
        entries.insert(Entry(delegate: delegate), at: 0)
    }

    /// Hands a call to the newest delegate that implements [selector] and has not had this call yet.
    ///
    /// Returns false when there is none, and the caller then completes the call itself.
    @discardableResult
    func forward(_ selector: Selector, _ call: (Delegate) -> Void) -> Bool {
        let reached = reachedByThisCall()
        let next = delegates().first {
            !reached.delegates.contains(identity($0)) && $0.responds(to: selector)
        }
        guard let next else { return false }
        let id = identity(next)
        reached.delegates.insert(id)
        defer { reached.delegates.remove(id) }
        call(next)
        return true
    }

    private func delegates() -> [Delegate] {
        lock.lock()
        defer { lock.unlock() }
        return entries.compactMap { $0.delegate }
    }

    private func reachedByThisCall() -> Reached {
        let thread = Thread.current.threadDictionary
        if let reached = thread[threadKey] as? Reached { return reached }
        let reached = Reached()
        thread[threadKey] = reached
        return reached
    }

    private func identity(_ delegate: Delegate) -> ObjectIdentifier {
        ObjectIdentifier(delegate as AnyObject)
    }
}
