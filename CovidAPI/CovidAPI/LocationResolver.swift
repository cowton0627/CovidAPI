import CoreLocation
import Foundation

struct CachedCoordinate: Codable, Equatable {
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees

    init(_ coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

protocol CoordinateCacheProtocol: AnyObject {
    func coordinate(for locationName: String) -> CLLocationCoordinate2D?
    func save(_ coordinate: CLLocationCoordinate2D, for locationName: String)
}

final class CoordinateCache: CoordinateCacheProtocol {
    private let defaults: UserDefaults
    private let key: String
    private var coordinates: [String: CachedCoordinate]

    init(defaults: UserDefaults = .standard, key: String = "epidemicCoordinateCache.v1") {
        self.defaults = defaults
        self.key = key
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: CachedCoordinate].self, from: data) {
            coordinates = decoded
        } else {
            coordinates = [:]
        }
    }

    func coordinate(for locationName: String) -> CLLocationCoordinate2D? {
        coordinates[locationName]?.coordinate
    }

    func save(_ coordinate: CLLocationCoordinate2D, for locationName: String) {
        coordinates[locationName] = CachedCoordinate(coordinate)
        guard let data = try? JSONEncoder().encode(coordinates) else { return }
        defaults.set(data, forKey: key)
    }
}

enum LocationNameNormalizer {
    private static let aliases: [(terms: [String], canonical: String)] = [
        (["中國大陸", "中國", "大陸地區"], "中國"),
        (["香港特別行政區", "香港"], "香港"),
        (["澳門特別行政區", "澳門"], "澳門"),
        (["韓國", "南韓"], "南韓"),
        (["北韓", "朝鮮"], "北韓"),
        (["美國", "USA", "United States"], "美國"),
        (["英國", "UK", "United Kingdom"], "英國"),
        (["俄羅斯", "俄國"], "俄羅斯"),
        (["越南", "越南共和國"], "越南"),
        (["剛果民主共和國", "剛果（金）", "剛果民主共和國(首都金夏沙)"], "剛果民主共和國"),
        (["剛果共和國", "剛果（布）"], "剛果共和國")
    ]

    private static let alertTerms = [
        "第一級", "第二級", "第三級", "注意", "警示", "警告", "旅遊疫情建議"
    ]

    static func normalize(_ headline: String) -> String {
        let standardized = headline
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")

        for alias in aliases {
            if alias.terms.contains(where: { standardized.localizedCaseInsensitiveContains($0) }) {
                return alias.canonical
            }
        }

        var cleaned = standardized
        alertTerms.forEach { cleaned = cleaned.replacingOccurrences(of: $0, with: "") }
        let separators = CharacterSet(charactersIn: "-－–—：:，,；;()[]【】")
        let candidate = cleaned.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        return candidate ?? headline.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
