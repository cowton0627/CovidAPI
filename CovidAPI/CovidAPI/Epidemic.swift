import Foundation
import UIKit

struct Epidemic: Codable, Equatable {
    let headline: String
    let effective: Date
    let description: String
}

enum AlertLevel: Int, CaseIterable {
    case watch = 1
    case alert = 2
    case warning = 3
    case unknown = 0

    static func from(epidemic: Epidemic) -> AlertLevel {
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
        case .unknown: return "未分類"
        }
    }
}
