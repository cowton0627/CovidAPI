import UIKit

final class FavoritesViewController: UITableViewController {
    private let allEpidemics: [Epidemic]
    private let favoriteStore: FavoriteStoreProtocol
    private var favoriteEpidemics: [Epidemic] = []

    init(epidemics: [Epidemic], favoriteStore: FavoriteStoreProtocol = FavoriteStore.shared) {
        allEpidemics = epidemics
        self.favoriteStore = favoriteStore
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "收藏地區"
        navigationItem.largeTitleDisplayMode = .never
        tableView.accessibilityIdentifier = "epidemic.favorites.list"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "FavoriteLocationCell")
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(favoritesDidChange),
            name: .epidemicFavoritesDidChange,
            object: nil
        )
        reloadFavorites()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        favoriteEpidemics.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let epidemic = favoriteEpidemics[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "FavoriteLocationCell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = epidemic.favoriteLocationKey
        let count = allEpidemics.filter { $0.favoriteLocationKey == epidemic.favoriteLocationKey }.count
        content.secondaryText = "\(epidemic.headline)・共 \(count) 筆"
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "epidemic.favorite.location.\(epidemic.favoriteLocationKey)"
        cell.accessibilityHint = "點兩下查看最新疫情資訊，也可向左滑動移除收藏"
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let detail = storyboard.instantiateViewController(withIdentifier: "DetailViewController") as? DetailViewController else { return }
        detail.epidemic = favoriteEpidemics[indexPath.row]
        detail.favoriteStore = favoriteStore
        navigationController?.pushViewController(detail, animated: true)
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let epidemic = favoriteEpidemics[indexPath.row]
        let remove = UIContextualAction(style: .destructive, title: "移除") { [weak self] _, _, completion in
            self?.favoriteStore.toggle(epidemic)
            completion(true)
        }
        remove.accessibilityLabel = "移除 \(epidemic.favoriteLocationKey) 收藏"
        return UISwipeActionsConfiguration(actions: [remove])
    }

    @objc private func favoritesDidChange() {
        reloadFavorites()
    }

    private func reloadFavorites() {
        let grouped = Dictionary(grouping: allEpidemics.filter(favoriteStore.contains), by: \.favoriteLocationKey)
        favoriteEpidemics = grouped.values.compactMap { epidemics in
            epidemics.max { $0.effective < $1.effective }
        }.sorted { $0.favoriteLocationKey.localizedStandardCompare($1.favoriteLocationKey) == .orderedAscending }
        tableView.reloadData()

        if favoriteEpidemics.isEmpty {
            let label = UILabel()
            label.text = "尚無收藏地區\n可從疫情詳細頁加入收藏"
            label.textColor = .secondaryLabel
            label.textAlignment = .center
            label.numberOfLines = 0
            label.font = .preferredFont(forTextStyle: .body)
            label.adjustsFontForContentSizeCategory = true
            label.accessibilityIdentifier = "epidemic.favorites.empty"
            tableView.backgroundView = label
        } else {
            tableView.backgroundView = nil
        }
    }
}
