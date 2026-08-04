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
   
    @IBSegueAction func showDetail(_ coder: NSCoder) -> DetailViewController? {
        let controller =  DetailViewController(coder: coder)
        if let row = tableView.indexPathForSelectedRow?.row {
            controller?.epidemic = viewModel.visibleEpidemics[row]
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
        navigationItem.titleView = filterControl

        viewModel.onChange = { [weak self] in
            self?.render()
        }
        viewModel.load()
    }
    
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        // #warning Incomplete implementation, return the number of sections
        return 1
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

    private func render() {
        refreshControl?.endRefreshing()
        tableView.reloadData()
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
            tableView.backgroundView = makeStateView(
                title: "沒有符合條件的資料",
                message: "請嘗試其他關鍵字或警示等級。"
            )
        case .failed(let message):
            tableView.backgroundView = makeStateView(
                title: "無法載入資料",
                message: message,
                retryAction: { [weak self] in self?.viewModel.refresh() }
            )
        }
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
        retryAction: (() -> Void)? = nil
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
