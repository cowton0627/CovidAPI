import Foundation

extension Notification.Name {
    static let epidemicFavoritesDidChange = Notification.Name("epidemicFavoritesDidChange")
}

protocol FavoriteStoreProtocol: AnyObject {
    func contains(_ epidemic: Epidemic) -> Bool
    func toggle(_ epidemic: Epidemic)
}

final class FavoriteStore: FavoriteStoreProtocol {
    static let shared = FavoriteStore()

    private let defaults: UserDefaults
    private let key: String
    private var favoriteKeys: Set<String>

    init(defaults: UserDefaults = .standard, key: String = "favoriteLocations.v1") {
        self.defaults = defaults
        self.key = key
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            defaults.removeObject(forKey: key)
        }
        favoriteKeys = Set(defaults.stringArray(forKey: key) ?? [])
    }

    func contains(_ epidemic: Epidemic) -> Bool {
        favoriteKeys.contains(epidemic.favoriteLocationKey)
    }

    func toggle(_ epidemic: Epidemic) {
        let locationKey = epidemic.favoriteLocationKey
        if favoriteKeys.contains(locationKey) {
            favoriteKeys.remove(locationKey)
        } else {
            favoriteKeys.insert(locationKey)
        }
        defaults.set(Array(favoriteKeys).sorted(), forKey: key)
        NotificationCenter.default.post(name: .epidemicFavoritesDidChange, object: self)
    }
}
