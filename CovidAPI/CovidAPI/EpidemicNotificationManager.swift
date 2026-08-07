import Foundation
import UserNotifications

extension Notification.Name {
    static let epidemicNotificationSelected = Notification.Name("epidemicNotificationSelected")
}

enum EpidemicNotificationRoute {
    static let identifierKey = "epidemicIdentifier"

    static func userInfo(for epidemic: Epidemic) -> [AnyHashable: Any] {
        [identifierKey: epidemic.notificationIdentifier]
    }

    static func identifier(from userInfo: [AnyHashable: Any]) -> String? {
        userInfo[identifierKey] as? String
    }
}

protocol EpidemicNotificationManaging: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(
        _ enabled: Bool,
        currentEpidemics: [Epidemic],
        completion: @escaping (Bool) -> Void
    )
    func process(_ epidemics: [Epidemic])
}

final class EpidemicNotificationTracker {
    private let defaults: UserDefaults
    private let key: String
    private var seenIdentifiers: Set<String>

    init(defaults: UserDefaults = .standard, key: String = "seenEpidemicNotifications.v1") {
        self.defaults = defaults
        self.key = key
        seenIdentifiers = Set(defaults.stringArray(forKey: key) ?? [])
    }

    func seed(_ epidemics: [Epidemic]) {
        saveSeen(epidemics.map(\.notificationIdentifier))
    }

    func newFavorites(
        in epidemics: [Epidemic],
        favoriteStore: FavoriteStoreProtocol
    ) -> [Epidemic] {
        let newItems = epidemics.filter {
            !seenIdentifiers.contains($0.notificationIdentifier) && favoriteStore.contains($0)
        }
        saveSeen(epidemics.map(\.notificationIdentifier))
        return newItems
    }

    private func saveSeen(_ identifiers: [String]) {
        seenIdentifiers.formUnion(identifiers)
        if seenIdentifiers.count > 1_000 {
            seenIdentifiers = Set(identifiers.suffix(1_000))
        }
        defaults.set(Array(seenIdentifiers).sorted(), forKey: key)
    }
}

final class EpidemicNotificationManager: EpidemicNotificationManaging {
    static let shared = EpidemicNotificationManager()

    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults
    private let favoriteStore: FavoriteStoreProtocol
    private let tracker: EpidemicNotificationTracker
    private let enabledKey = "favoriteNotificationsEnabled.v1"

    var isEnabled: Bool {
        defaults.bool(forKey: enabledKey)
    }

    init(
        center: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard,
        favoriteStore: FavoriteStoreProtocol = FavoriteStore.shared,
        tracker: EpidemicNotificationTracker? = nil
    ) {
        self.center = center
        self.defaults = defaults
        self.favoriteStore = favoriteStore
        self.tracker = tracker ?? EpidemicNotificationTracker(defaults: defaults)
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-notification-denied") {
            defaults.set(false, forKey: enabledKey)
        }
    }

    func setEnabled(
        _ enabled: Bool,
        currentEpidemics: [Epidemic],
        completion: @escaping (Bool) -> Void
    ) {
        guard enabled else {
            defaults.set(false, forKey: enabledKey)
            completion(false)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-notification-denied") {
            defaults.set(false, forKey: enabledKey)
            completion(false)
            return
        }

        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            guard let self = self else { return }
            if granted {
                self.tracker.seed(currentEpidemics)
            }
            self.defaults.set(granted, forKey: self.enabledKey)
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func process(_ epidemics: [Epidemic]) {
        guard isEnabled else { return }
        let newItems = tracker.newFavorites(in: epidemics, favoriteStore: favoriteStore)
        for epidemic in newItems.prefix(5) {
            let content = UNMutableNotificationContent()
            content.title = "收藏地區有新疫情資訊"
            content.body = epidemic.headline
            content.sound = .default
            content.userInfo = EpidemicNotificationRoute.userInfo(for: epidemic)
            let request = UNNotificationRequest(
                identifier: epidemic.notificationIdentifier,
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }
}
