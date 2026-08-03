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

    var title: String {
        switch self {
        case .all: return "全部"
        case .warning: return "三級"
        case .alert: return "二級"
        case .watch: return "一級"
        }
    }

    var alertLevel: AlertLevel? {
        switch self {
        case .all: return nil
        case .warning: return .warning
        case .alert: return .alert
        case .watch: return .watch
        }
    }
}

final class EpidemicListViewModel {
    var onChange: (() -> Void)?

    private let repository: EpidemicRepository
    private(set) var state: EpidemicListState = .loading
    private(set) var allEpidemics: [Epidemic] = []
    private(set) var visibleEpidemics: [Epidemic] = []
    private(set) var updatedAt: Date?
    private(set) var isShowingCachedData = false
    private var query = ""
    private var filter: AlertFilter = .all

    init(repository: EpidemicRepository = .shared) {
        self.repository = repository
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

    private func apply(_ snapshot: EpidemicSnapshot) {
        allEpidemics = snapshot.epidemics.sorted { $0.effective > $1.effective }
        updatedAt = snapshot.updatedAt
        isShowingCachedData = snapshot.isFromCache
        applyFilters()
    }

    private func applyFilters() {
        visibleEpidemics = allEpidemics.filter { epidemic in
            let matchesLevel = filter.alertLevel.map {
                AlertLevel.from(epidemic: epidemic) == $0
            } ?? true
            let matchesQuery = query.isEmpty ||
                epidemic.headline.localizedCaseInsensitiveContains(query) ||
                epidemic.description.localizedCaseInsensitiveContains(query)
            return matchesLevel && matchesQuery
        }
        state = visibleEpidemics.isEmpty ? .empty : .loaded
        onChange?()
    }
}
