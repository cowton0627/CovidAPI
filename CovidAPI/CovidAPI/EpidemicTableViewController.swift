//
//  EpidemicTableViewController.swift
//  CovidAPI
//  Created by 鄭淳澧 on 2021/5/31.
//

import UIKit

class EpidemicTableViewCell: UITableViewCell {

    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var ourbreakDayLabel: UILabel!
    
}


class EpidemicTableViewController: UITableViewController {
    private let viewModel = EpidemicListViewModel()
    private let searchController = UISearchController(searchResultsController: nil)
    private let filterControl = UISegmentedControl(items: AlertFilter.allCases.map(\.title))
    private let notificationManager = EpidemicNotificationManager.shared
    private var showsFavoritesOnly = false
    private var sortMode: EpidemicSortMode = .newest
    private var pendingNotificationIdentifier: String?
   
    @IBSegueAction func showDetail(_ coder: NSCoder) -> DetailViewController? {
        let controller =  DetailViewController(coder: coder)
        if let row = tableView.indexPathForSelectedRow?.row {
            controller?.epidemic = viewModel.visibleEpidemics[row]
            controller?.favoriteStore = FavoriteStore.shared
        }
        return controller
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always

        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 88
        tableView.accessibilityIdentifier = "epidemic.list"

        refreshControl = UIRefreshControl()
        refreshControl?.accessibilityIdentifier = "epidemic.refresh"
        refreshControl?.accessibilityLabel = "重新整理疫情資料"
        refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "搜尋國家、地區或疾病"
        searchController.searchBar.searchTextField.accessibilityIdentifier = "epidemic.search"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

        filterControl.selectedSegmentIndex = AlertFilter.all.rawValue
        filterControl.addTarget(self, action: #selector(filterChanged), for: .valueChanged)
        filterControl.selectedSegmentTintColor = .systemOrange
        filterControl.accessibilityIdentifier = "epidemic.filter"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "star"),
            menu: makeFavoritesMenu()
        )
        navigationItem.leftBarButtonItem?.accessibilityIdentifier = "epidemic.favorites.filter"
        updateFavoritesMenu()
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: nil,
            style: .plain,
            target: self,
            action: #selector(toggleNotifications)
        )
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "epidemic.notifications.toggle"
        updateNotificationsButton()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(favoritesDidChange),
            name: .epidemicFavoritesDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(epidemicNotificationSelected(_:)),
            name: .epidemicNotificationSelected,
            object: nil
        )

        viewModel.onChange = { [weak self] in
            self?.render()
        }
        viewModel.load()
        configureUITestingNotificationRoute()
    }

    @objc private func epidemicNotificationSelected(_ notification: Notification) {
        guard let identifier = EpidemicNotificationRoute.identifier(from: notification.userInfo ?? [:]) else { return }
        pendingNotificationIdentifier = identifier
        openPendingNotificationIfAvailable()
    }

    private func configureUITestingNotificationRoute() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "--ui-testing-notification"),
              arguments.indices.contains(flagIndex + 1) else { return }
        pendingNotificationIdentifier = arguments[flagIndex + 1]
    }

    private func openPendingNotificationIfAvailable() {
        guard let identifier = pendingNotificationIdentifier,
              let epidemic = viewModel.allEpidemics.first(where: { $0.notificationIdentifier == identifier }),
              let detail = storyboard?.instantiateViewController(withIdentifier: "DetailViewController") as? DetailViewController else { return }
        pendingNotificationIdentifier = nil
        showsFavoritesOnly = false
        searchController.searchBar.text = nil
        filterControl.selectedSegmentIndex = AlertFilter.all.rawValue
        viewModel.setSearchQuery("")
        viewModel.setFilter(.all)
        viewModel.setShowsFavoritesOnly(false)
        detail.epidemic = epidemic
        detail.favoriteStore = FavoriteStore.shared
        navigationController?.popToRootViewController(animated: false)
        navigationController?.pushViewController(detail, animated: true)
    }

    
    override func numberOfSections(in tableView: UITableView) -> Int {
        // #warning Incomplete implementation, return the number of sections
        return 1
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        52
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = UIView()
        header.backgroundColor = .systemBackground
        filterControl.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(filterControl)
        NSLayoutConstraint.activate([
            filterControl.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            filterControl.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),
            filterControl.topAnchor.constraint(equalTo: header.topAnchor, constant: 8),
            filterControl.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -8)
        ])
        return header
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        return viewModel.visibleEpidemics.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "outBreakCell", for: indexPath) as! EpidemicTableViewCell
        let epidemic = viewModel.visibleEpidemics[indexPath.row]

        let alertLevel = AlertLevel.from(epidemic: epidemic)
        let symbolConfig = UIImage.SymbolConfiguration(textStyle: .headline)
        let symbolName = alertLevel == .unknown ? "questionmark.circle.fill" : "exclamationmark.triangle.fill"
        let icon = UIImage(systemName: symbolName, withConfiguration: symbolConfig)?
            .withTintColor(alertLevel.color, renderingMode: .alwaysOriginal)
        let attachment = NSTextAttachment()
        attachment.image = icon
        let titleText = NSMutableAttributedString(attachment: attachment)
        titleText.append(NSAttributedString(string: "  \(epidemic.headline)"))
        titleText.addAttribute(
            .font,
            value: UIFont.preferredFont(forTextStyle: .headline),
            range: NSRange(location: 0, length: titleText.length)
        )
        cell.titleLabel.attributedText = titleText
        cell.titleLabel.adjustsFontForContentSizeCategory = true

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        cell.ourbreakDayLabel.text = formatter.string(from: epidemic.effective)
        cell.ourbreakDayLabel.font = .preferredFont(forTextStyle: .subheadline)
        cell.ourbreakDayLabel.adjustsFontForContentSizeCategory = true

        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "epidemic.cell.\(indexPath.row)"
        cell.isAccessibilityElement = true
        let levelDescription = alertLevel == .unknown ? "疾管署未提供等級" : alertLevel.label
        cell.accessibilityLabel = "\(epidemic.headline)，\(levelDescription)，發布日 \(cell.ourbreakDayLabel.text ?? "")"
        cell.accessibilityHint = "點兩下查看疫情詳細資訊"
        return cell
    }
    
    
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

    
    @objc func refresh() {
        viewModel.refresh()
    }

    @objc private func filterChanged() {
        guard let filter = AlertFilter(rawValue: filterControl.selectedSegmentIndex) else { return }
        viewModel.setFilter(filter)
    }

    @objc private func toggleFavoritesFilter() {
        showsFavoritesOnly.toggle()
        viewModel.setShowsFavoritesOnly(showsFavoritesOnly)
        updateFavoritesMenu()
    }

    @objc private func favoritesDidChange() {
        viewModel.favoritesDidChange()
    }

    private func updateFavoritesMenu() {
        navigationItem.leftBarButtonItem?.image = UIImage(
            systemName: showsFavoritesOnly ? "star.fill" : "star"
        )
        navigationItem.leftBarButtonItem?.accessibilityLabel = "收藏與篩選"
        navigationItem.leftBarButtonItem?.menu = makeFavoritesMenu()
    }

    private func makeFavoritesMenu() -> UIMenu {
        let filter = UIAction(
            title: "只顯示收藏地區",
            image: UIImage(systemName: showsFavoritesOnly ? "star.fill" : "star"),
            state: showsFavoritesOnly ? .on : .off
        ) { [weak self] _ in
            self?.toggleFavoritesFilter()
        }
        let manage = UIAction(
            title: "管理收藏地區",
            image: UIImage(systemName: "list.bullet")
        ) { [weak self] _ in
            self?.showFavoritesManager()
        }
        let newest = UIAction(
            title: "依發布時間",
            image: UIImage(systemName: "calendar"),
            state: sortMode == .newest ? .on : .off
        ) { [weak self] _ in
            self?.setSortMode(.newest)
        }
        let severity = UIAction(
            title: "依疫情等級",
            image: UIImage(systemName: "exclamationmark.triangle"),
            state: sortMode == .severity ? .on : .off
        ) { [weak self] _ in
            self?.setSortMode(.severity)
        }
        let reset = UIAction(
            title: "重設檢視條件",
            image: UIImage(systemName: "arrow.counterclockwise")
        ) { [weak self] _ in
            self?.resetViewOptions()
        }
        let favorites = UIMenu(options: .displayInline, children: [filter, manage])
        let sorting = UIMenu(title: "排序方式", options: .displayInline, children: [newest, severity])
        return UIMenu(children: [favorites, sorting, reset])
    }

    private func setSortMode(_ sortMode: EpidemicSortMode) {
        self.sortMode = sortMode
        viewModel.setSortMode(sortMode)
        updateFavoritesMenu()
    }

    private func resetViewOptions() {
        showsFavoritesOnly = false
        sortMode = .newest
        searchController.searchBar.text = nil
        searchController.isActive = false
        filterControl.selectedSegmentIndex = AlertFilter.all.rawValue
        viewModel.resetViewOptions()
        updateFavoritesMenu()
    }

    private func showFavoritesManager() {
        let controller = FavoritesViewController(epidemics: viewModel.allEpidemics)
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func toggleNotifications() {
        let shouldEnable = !notificationManager.isEnabled
        notificationManager.setEnabled(
            shouldEnable,
            currentEpidemics: viewModel.allEpidemics
        ) { [weak self] enabled in
            self?.updateNotificationsButton()
            if shouldEnable && !enabled {
                self?.showNotificationPermissionDeniedAlert()
            }
        }
    }

    private func updateNotificationsButton() {
        let enabled = notificationManager.isEnabled
        navigationItem.rightBarButtonItem?.image = UIImage(
            systemName: enabled ? "bell.fill" : "bell"
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = enabled
            ? "關閉收藏地區新疫情通知"
            : "開啟收藏地區新疫情通知"
    }

    private func showNotificationPermissionDeniedAlert() {
        let alert = UIAlertController(
            title: "無法開啟通知",
            message: "請至系統設定允許 CovidAPI 傳送通知。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "前往設定", style: .default) { _ in
            guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(settingsURL)
        })
        present(alert, animated: true)
    }

    private func render() {
        refreshControl?.endRefreshing()
        tableView.reloadData()
        tableView.tableFooterView = nil
        updateFilterAvailability()

        switch viewModel.state {
        case .loading:
            tableView.backgroundView = makeStateView(
                title: "正在取得旅遊疫情資訊",
                message: "請稍候…",
                showActivity: true
            )
        case .loaded:
            tableView.backgroundView = nil
            tableView.tableFooterView = makeUpdatedFooter()
        case .empty:
            let message = showsFavoritesOnly
                ? "尚無符合條件的收藏地區，可從詳細頁加入收藏。"
                : "請嘗試其他關鍵字或警示等級。"
            tableView.backgroundView = makeStateView(
                title: "沒有符合條件的資料",
                message: message,
                actionTitle: "重設檢視條件",
                actionIdentifier: "epidemic.reset",
                action: { [weak self] in self?.resetViewOptions() }
            )
        case .failed(let message):
            tableView.backgroundView = makeStateView(
                title: "無法載入資料",
                message: message,
                retryAction: { [weak self] in self?.viewModel.refresh() }
            )
        }
        openPendingNotificationIfAvailable()
    }

    private func updateFilterAvailability() {
        for filter in AlertFilter.allCases where filter != .all {
            let hasMatchingData = viewModel.allEpidemics.contains(where: filter.matches)
            filterControl.setEnabled(hasMatchingData, forSegmentAt: filter.rawValue)
        }
        let unknownCount = viewModel.allEpidemics.filter {
            AlertLevel.from(epidemic: $0) == .unknown
        }.count
        let summary = unknownCount == 0
            ? "所有資料均有疾管署旅遊疫情等級"
            : "疾管署未提供等級：\(unknownCount) 筆"
        filterControl.accessibilityHint = summary
    }

    private func makeUpdatedFooter() -> UIView? {
        guard let updatedAt = viewModel.updatedAt else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hant_TW")
        formatter.dateFormat = "yyyy/MM/dd HH:mm"

        let label = UILabel()
        let source = viewModel.isShowingCachedData ? "離線資料" : "疾管署資料"
        let unknownCount = viewModel.allEpidemics.filter {
            AlertLevel.from(epidemic: $0) == .unknown
        }.count
        let levelNote = unknownCount > 0 ? "・未分級 \(unknownCount) 筆" : ""
        label.text = "\(source)・更新於 \(formatter.string(from: updatedAt))\(levelNote)"
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.frame.size.height = 44
        label.adjustsFontForContentSizeCategory = true
        label.accessibilityIdentifier = "epidemic.updatedAt"
        return label
    }

    private func makeStateView(
        title: String,
        message: String,
        showActivity: Bool = false,
        retryAction: (() -> Void)? = nil,
        actionTitle: String? = nil,
        actionIdentifier: String? = nil,
        action: (() -> Void)? = nil
    ) -> UIView {
        let container = UIView()
        container.accessibilityIdentifier = "epidemic.state"
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        if showActivity {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.startAnimating()
            stack.addArrangedSubview(indicator)
        }

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        stack.addArrangedSubview(titleLabel)

        let messageLabel = UILabel()
        messageLabel.text = message
        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.adjustsFontForContentSizeCategory = true
        stack.addArrangedSubview(messageLabel)

        if let retryAction = retryAction {
            let button = RetryButton(type: .system)
            button.setTitle("重試", for: .normal)
            button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
            button.action = retryAction
            button.accessibilityIdentifier = "epidemic.retry"
            stack.addArrangedSubview(button)
        }

        if let actionTitle, let action {
            let button = RetryButton(type: .system)
            button.setTitle(actionTitle, for: .normal)
            button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
            button.action = action
            button.accessibilityIdentifier = actionIdentifier
            stack.addArrangedSubview(button)
        }

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24)
        ])
        return container
    }
    
    
}

extension EpidemicTableViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        viewModel.setSearchQuery(searchController.searchBar.text ?? "")
    }
}

private final class RetryButton: UIButton {
    var action: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    @objc private func tapped() {
        action?()
    }
}
