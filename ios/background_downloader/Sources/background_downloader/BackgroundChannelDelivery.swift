//
//  BackgroundChannelDelivery.swift
//  background_downloader
//
//  [DLCT] Delivery of native -> Dart updates on the background channel.
//
//  This file has no Flutter dependency so its logic can be compiled and
//  exercised outside the plugin.
//

import Foundation

/// Pure decisions for posting an update to Dart on the background channel
enum BackgroundChannelDelivery {
    /// How long a post waits for Dart to answer before it is treated as not
    /// delivered (and the update is stored locally)
    static let replyTimeout: DispatchTimeInterval = .seconds(2)

    /// True only if [reply] is the boolean `true` that the Dart handler
    /// returns for every message it handled.
    ///
    /// `nil` (the engine dropped the message, or no handler answered),
    /// `FlutterMethodNotImplemented`, a `FlutterError`, the number `1`, or any
    /// other value means the update was not delivered. The standard codec
    /// decodes Dart `true` as `kCFBooleanTrue`, so the check is on the
    /// CFBoolean type rather than on `as? Bool`, which also accepts `1`.
    static func isDeliveredReply(_ reply: Any?) -> Bool {
        guard let number = reply as? NSNumber else {
            return false
        }
        return CFGetTypeID(number) == CFBooleanGetTypeID() && number.boolValue
    }

    /// True when updates may be posted to Dart instead of stored locally:
    /// the Dart side has confirmed its background channel handler is set, and
    /// the app has asked for delivery (popped its stored updates, or made the
    /// call that would have created the URLSession without a required-flags
    /// declaration)
    static func isDartReady(handlerConfirmed: Bool, deliveryDemanded: Bool) -> Bool {
        return handlerConfirmed && deliveryDemanded
    }

    /// True if an update must be stored locally for replay, rather than
    /// counted as delivered
    static func shouldStoreLocally(dartReady: Bool, replied: Bool, reply: Any?, forceFail: Bool) -> Bool {
        return forceFail || !dartReady || !replied || !isDeliveredReply(reply)
    }
}

/// An update that is stored locally if it cannot be delivered to Dart
struct UndeliveredItem {
    /// UserDefaults key of the map (keyed by taskId) the update is stored in
    let prefsKey: String
    let taskId: String
    /// Produces the stored JSON representation, or nil if it cannot be encoded
    let encode: () -> Data?
}

/// An update as written to the local store
struct StoredUndelivered: Equatable {
    let prefsKey: String
    let taskId: String
    let value: String
}

/// Result of offering an update to the store before posting it
enum PreReadyDecision: Equatable {
    /// Dart is ready: post the update
    case dartReady
    /// Dart is not ready and the update was stored locally
    case stored(StoredUndelivered)
    /// Dart is not ready and there was nothing to store (or encoding failed)
    case notStored
}

/// Locally stored updates that could not be delivered to Dart, plus the Dart
/// readiness state that decides whether an update is posted or stored.
///
/// One lock guards the readiness state and every read-modify-write of the
/// stored maps. Because the readiness check and the store of a not-ready
/// update happen in one lock hold, and a pop marks delivery as demanded in the
/// same hold as it reads and clears the map, every update stored because Dart
/// was not ready is either returned by a pop or stored before readiness
/// flipped.
final class UndeliveredStore: @unchecked Sendable {
    static let shared = UndeliveredStore(defaults: UserDefaults.standard)

    private let lock = NSLock()
    private let defaults: UserDefaults
    private var handlerConfirmed = false
    private var deliveryDemanded = false
    /// TaskIds present in each stored map, loaded from defaults on first use
    private var storedTaskIds = [String: Set<String>]()

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var isDartReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return readyLocked
    }

    /// Records that the Dart background channel handler is set.
    ///
    /// Returns true if this made Dart ready
    func confirmDartHandler() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let wasReady = readyLocked
        handlerConfirmed = true
        return !wasReady && readyLocked
    }

    /// Records that the app asked for updates to flow.
    ///
    /// Returns true if this made Dart ready
    func demandDelivery() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let wasReady = readyLocked
        deliveryDemanded = true
        return !wasReady && readyLocked
    }

    /// Stores [item] if Dart is not ready; tells the caller to post otherwise
    func storeUnlessDartReady(_ item: UndeliveredItem?) -> PreReadyDecision {
        lock.lock()
        defer { lock.unlock() }
        if readyLocked {
            return .dartReady
        }
        guard let stored = storeLocked(item) else {
            return .notStored
        }
        return .stored(stored)
    }

    /// Stores [item] regardless of readiness (used when a post was not
    /// delivered). Returns what was stored, or nil
    func store(_ item: UndeliveredItem?) -> StoredUndelivered? {
        lock.lock()
        defer { lock.unlock() }
        return storeLocked(item)
    }

    /// Removes [stored] if the entry for its taskId is still exactly that
    /// value; used when Dart confirms, after the timeout, a post whose update
    /// was already stored
    func removeIfUnchanged(_ stored: StoredUndelivered) {
        lock.lock()
        defer { lock.unlock() }
        var map = defaults.dictionary(forKey: stored.prefsKey) ?? [:]
        guard map[stored.taskId] as? String == stored.value else {
            return
        }
        map.removeValue(forKey: stored.taskId)
        defaults.set(map, forKey: stored.prefsKey)
        storedTaskIds[stored.prefsKey]?.remove(stored.taskId)
    }

    /// Removes the stored entry for [taskId] in [prefsKey] after a newer
    /// update of the same kind was delivered live, so a later pop does not
    /// replay the older update after the newer one
    func removeSuperseded(prefsKey: String, taskId: String) {
        lock.lock()
        defer { lock.unlock() }
        guard taskIdsLocked(prefsKey).contains(taskId) else {
            return
        }
        var map = defaults.dictionary(forKey: prefsKey) ?? [:]
        map.removeValue(forKey: taskId)
        defaults.set(map, forKey: prefsKey)
        storedTaskIds[prefsKey]?.remove(taskId)
    }

    /// Marks delivery as demanded, then returns and clears the stored map for
    /// [prefsKey], in one lock hold.
    ///
    /// Returns the map (nil if none was stored) and whether this made Dart ready
    func pop(prefsKey: String) -> (map: [String: Any]?, becameReady: Bool) {
        lock.lock()
        defer { lock.unlock() }
        let wasReady = readyLocked
        deliveryDemanded = true
        let map = defaults.dictionary(forKey: prefsKey)
        defaults.removeObject(forKey: prefsKey)
        storedTaskIds[prefsKey] = []
        return (map, !wasReady && readyLocked)
    }

    private var readyLocked: Bool {
        return BackgroundChannelDelivery.isDartReady(handlerConfirmed: handlerConfirmed,
                                                     deliveryDemanded: deliveryDemanded)
    }

    private func taskIdsLocked(_ prefsKey: String) -> Set<String> {
        if let taskIds = storedTaskIds[prefsKey] {
            return taskIds
        }
        let taskIds = Set((defaults.dictionary(forKey: prefsKey) ?? [:]).keys)
        storedTaskIds[prefsKey] = taskIds
        return taskIds
    }

    private func storeLocked(_ item: UndeliveredItem?) -> StoredUndelivered? {
        guard let item = item,
              let data = item.encode(),
              let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        var taskIds = taskIdsLocked(item.prefsKey)
        var map = defaults.dictionary(forKey: item.prefsKey) ?? [:]
        map[item.taskId] = value
        defaults.set(map, forKey: item.prefsKey)
        taskIds.insert(item.taskId)
        storedTaskIds[item.prefsKey] = taskIds
        return StoredUndelivered(prefsKey: item.prefsKey, taskId: item.taskId, value: value)
    }
}

/// The reply slot of one blocking post: whichever of the reply and the
/// timeout comes first decides the outcome, under a lock, so a reply that
/// arrives after the timeout can never also count as delivered
final class BackgroundReplySlot: @unchecked Sendable {
    enum Outcome {
        /// Dart replied in time with this value
        case replied(Any?)
        /// No reply in time; carries what was stored locally, if anything
        case timedOut(StoredUndelivered?)
    }

    private enum State {
        case waiting
        case replied(Any?)
        case timedOut(StoredUndelivered?)
    }

    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var state = State.waiting

    /// Called with Dart's reply. [confirmsDelivery] is the caller's verdict on
    /// that reply.
    ///
    /// Returns the stored update to remove when this reply confirms delivery
    /// of a post that had already timed out and been stored, else nil
    func receive(_ reply: Any?, confirmsDelivery: Bool) -> StoredUndelivered? {
        lock.lock()
        defer { lock.unlock() }
        switch state {
        case .waiting:
            state = .replied(reply)
            semaphore.signal()
            return nil
        case .timedOut(let stored):
            state = .timedOut(nil) // a second reply cannot remove anything
            return confirmsDelivery ? stored : nil
        case .replied:
            return nil
        }
    }

    /// Waits up to [timeout] for the reply. On timeout, [storeOnTimeout] runs
    /// while the slot is locked, so a late reply sees the stored update
    func wait(timeout: DispatchTimeInterval, storeOnTimeout: () -> StoredUndelivered?) -> Outcome {
        _ = semaphore.wait(timeout: .now() + timeout)
        lock.lock()
        defer { lock.unlock() }
        if case .replied(let reply) = state {
            return .replied(reply)
        }
        let stored = storeOnTimeout()
        state = .timedOut(stored)
        return .timedOut(stored)
    }
}
