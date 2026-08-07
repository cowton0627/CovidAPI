import Foundation

enum EpidemicListState {
    case loading
    case loaded
    case empty
    case failed(String)
}

enum AlertFilter: Int, CaseIterable {
    case all
    case warning
    case alert
    case watch
    case unknown

    var title: String {
        switch self {
        case .all: return "全部"
        case .warning: return "三級"
        case .alert: return "二級"
        case .watch: return "一級"
        case .unknown: return "未分級"
        }
    }

    func matches(_ epidemic: Epidemic) -> Bool {
        switch self {
        case .all: return true
        case .warning: return AlertLevel.from(epidemic: epidemic) == .warning
        case .alert: return AlertLevel.from(epidemic: epidemic) == .alert
        case .watch: return AlertLevel.from(epidemic: epidemic) == .watch
        case .unknown: return AlertLevel.from(epidemic: epidemic) == .unknown
        }
    }
}

enum EpidemicSortMode {
    case newest
    case severity
}

final class EpidemicListViewModel {
    var onChange: (() -> Void)?

    private let repository: EpidemicRepository
    private let favoriteStore: FavoriteStoreProtocol
    private let notificationManager: EpidemicNotificationManaging
    private(set) var state: EpidemicListState = .loading
    private(set) var allEpidemics: [Epidemic] = []
    private(set) var visibleEpidemics: [Epidemic] = []
    private(set) var updatedAt: Date?
    private(set) var isShowingCachedData = false
    private var query = ""
    private var filter: AlertFilter = .all
    private var showsFavoritesOnly = false
    private var sortMode: EpidemicSortMode = .newest

    init(
        repository: EpidemicRepository = .shared,
        favoriteStore: FavoriteStoreProtocol = FavoriteStore.shared,
        notificationManager: EpidemicNotificationManaging = EpidemicNotificationManager.shared
    ) {
        self.repository = repository
        self.favoriteStore = favoriteStore
        self.notificationManager = notificationManager
    }

    func load() {
        if let snapshot = repository.cachedSnapshot() {
            apply(snapshot)
        } else {
            state = .loading
            onChange?()
        }
        refresh()
    }

    func refresh() {
        repository.refresh { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let snapshot):
                self.apply(snapshot)
            case .failure(let error):
                self.state = .failed(error.localizedDescription)
                self.onChange?()
            }
        }
    }

    func setSearchQuery(_ query: String) {
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        applyFilters()
    }

    func setFilter(_ filter: AlertFilter) {
        self.filter = filter
        applyFilters()
    }

    func setShowsFavoritesOnly(_ showsFavoritesOnly: Bool) {
        self.showsFavoritesOnly = showsFavoritesOnly
        applyFilters()
    }

    func setSortMode(_ sortMode: EpidemicSortMode) {
        self.sortMode = sortMode
        applyFilters()
    }

    func favoritesDidChange() {
        applyFilters()
    }

    private func apply(_ snapshot: EpidemicSnapshot) {
        allEpidemics = snapshot.epidemics.sorted { $0.effective > $1.effective }
        updatedAt = snapshot.updatedAt
        isShowingCachedData = snapshot.isFromCache
        if !snapshot.isFromCache {
            notificationManager.process(snapshot.epidemics)
        }
        applyFilters()
    }

    private func applyFilters() {
        visibleEpidemics = allEpidemics.filter { epidemic in
            let matchesLevel = filter.matches(epidemic)
            let matchesFavorite = !showsFavoritesOnly || favoriteStore.contains(epidemic)
            let matchesQuery = query.isEmpty ||
                epidemic.headline.localizedCaseInsensitiveContains(query) ||
                epidemic.description.localizedCaseInsensitiveContains(query)
            return matchesLevel && matchesFavorite && matchesQuery
        }.sorted { lhs, rhs in
            switch sortMode {
            case .newest:
                return lhs.effective > rhs.effective
            case .severity:
                let leftLevel = AlertLevel.from(epidemic: lhs).rawValue
                let rightLevel = AlertLevel.from(epidemic: rhs).rawValue
                if leftLevel != rightLevel {
                    return leftLevel > rightLevel
                }
                return lhs.effective > rhs.effective
            }
        }
        state = visibleEpidemics.isEmpty ? .empty : .loaded
        onChange?()
    }
}
