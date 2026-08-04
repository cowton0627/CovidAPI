import Foundation
import UIKit

struct Epidemic: Codable, Equatable {
    let headline: String
    let effective: Date
    let description: String
    let severityLevel: Int?
    let areaDescription: String?

    init(
        headline: String,
        effective: Date,
        description: String,
        severityLevel: Int? = nil,
        areaDescription: String? = nil
    ) {
        self.headline = headline
        self.effective = effective
        self.description = description
        self.severityLevel = severityLevel
        self.areaDescription = areaDescription
    }

    private enum CodingKeys: String, CodingKey {
        case headline
        case effective
        case description
        case severityLevel = "severity_level"
        case areaDescription = "areaDesc"
    }

    var favoriteLocationKey: String {
        let area = areaDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        return area.flatMap { $0.isEmpty ? nil : $0 } ?? LocationNameNormalizer.normalize(headline)
    }

    var notificationIdentifier: String {
        "\(headline)|\(effective.timeIntervalSince1970)"
    }
}

enum AlertLevel: Int, CaseIterable {
    case watch = 1
    case alert = 2
    case warning = 3
    case unknown = 0

    static func from(epidemic: Epidemic) -> AlertLevel {
        if let level = epidemic.severityLevel, let alertLevel = AlertLevel(rawValue: level) {
            return alertLevel
        }
        let text = epidemic.headline + epidemic.description
        if text.contains("第三級") || text.contains("警告") {
            return .warning
        }
        if text.contains("第二級") || text.contains("警示") {
            return .alert
        }
        if text.contains("第一級") || text.contains("注意") {
            return .watch
        }
        return .unknown
    }

    var color: UIColor {
        switch self {
        case .watch: return .systemYellow
        case .alert: return .systemOrange
        case .warning: return .systemRed
        case .unknown: return .systemGray
        }
    }

    var glyphText: String {
        self == .unknown ? "?" : String(rawValue)
    }

    var label: String {
        switch self {
        case .watch: return "第一級 注意"
        case .alert: return "第二級 警示"
        case .warning: return "第三級 警告"
        case .unknown: return "未分級"
        }
    }
}
