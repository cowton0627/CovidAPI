//
//  DetailViewController.swift
//  CovidAPI
//
//  Created by 鄭淳澧 on 2021/6/2.
//

import UIKit

class DetailViewCell: UITableViewCell {
    
    @IBOutlet weak var describeLabel: UILabel!
    
}

class DetailViewController: UITableViewController {
    var epidemic: Epidemic!
    var favoriteStore: FavoriteStoreProtocol = FavoriteStore.shared
    
    //    init?(coder: NSCoder, epidemic: Epidemic) {
    //          self.epidemic = epidemic
    //          super.init(coder: coder)
    //       }
    //       required init?(coder: NSCoder) {
    //          fatalError()
    //       }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = epidemic.headline
        navigationItem.largeTitleDisplayMode = .never
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 300
        tableView.separatorStyle = .none
        tableView.accessibilityIdentifier = "epidemic.detail"
        let favoriteButton = UIBarButtonItem(
            image: nil,
            style: .plain,
            target: self,
            action: #selector(toggleFavorite)
        )
        favoriteButton.accessibilityIdentifier = "epidemic.favorite.toggle"
        let shareButton = UIBarButtonItem(
            barButtonSystemItem: .action,
            target: self,
            action: #selector(shareEpidemic)
        )
        shareButton.accessibilityIdentifier = "epidemic.share"
        shareButton.accessibilityLabel = "分享疫情資訊"
        navigationItem.rightBarButtonItems = [favoriteButton, shareButton]
        configureMapButton()
        updateFavoriteButton()
    }

    @objc private func toggleFavorite() {
        favoriteStore.toggle(epidemic)
        updateFavoriteButton()
    }

    @objc private func shareEpidemic(_ sender: UIBarButtonItem) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        let level = AlertLevel.from(epidemic: epidemic).label
        let text = """
        \(epidemic.headline)
        \(level)・發布日 \(formatter.string(from: epidemic.effective))

        \(epidemic.description)

        資料來源：衛生福利部疾病管制署
        """
        let sourceURL = URL(string: "https://www.cdc.gov.tw/TravelEpidemic/ExportJSON")!
        let activity = UIActivityViewController(activityItems: [text, sourceURL], applicationActivities: nil)
        activity.popoverPresentationController?.barButtonItem = sender
        present(activity, animated: true)
    }

    @objc private func showOnMap() {
        guard let tabBarController = tabBarController,
              let mapNavigationController = tabBarController.viewControllers?.last as? UINavigationController,
              let mapController = mapNavigationController.viewControllers.first as? MapViewController else { return }
        tabBarController.selectedViewController = mapNavigationController
        mapNavigationController.popToRootViewController(animated: false)
        mapController.focus(on: epidemic)
    }

    private func configureMapButton() {
        let button = UIButton(type: .system)
        button.setTitle("在地圖查看", for: .normal)
        button.setImage(UIImage(systemName: "map"), for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.accessibilityIdentifier = "epidemic.detail.showOnMap"
        button.addTarget(self, action: #selector(showOnMap), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 64))
        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        tableView.tableFooterView = container
    }

    private func updateFavoriteButton() {
        let isFavorite = favoriteStore.contains(epidemic)
        let favoriteButton = navigationItem.rightBarButtonItems?.first
        favoriteButton?.image = UIImage(
            systemName: isFavorite ? "star.fill" : "star"
        )
        favoriteButton?.accessibilityLabel = isFavorite ? "取消收藏地區" : "收藏地區"
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        // #warning Incomplete implementation, return the number of sections
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        return 1
    }

    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "detailViewCell", for: indexPath) as! DetailViewCell

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        let dateString = formatter.string(from: epidemic.effective)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 8

        let attributed = NSMutableAttributedString()
        attributed.append(NSAttributedString(string: dateString + "\n\n", attributes: [
            .font: UIFont.preferredFont(forTextStyle: .footnote),
            .foregroundColor: UIColor.secondaryLabel,
            .paragraphStyle: paragraphStyle
        ]))
        attributed.append(NSAttributedString(string: epidemic.description, attributes: [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraphStyle
        ]))

        cell.describeLabel.attributedText = attributed
        cell.describeLabel.numberOfLines = 0
        cell.describeLabel.adjustsFontForContentSizeCategory = true
        cell.describeLabel.accessibilityIdentifier = "epidemic.detail.description"
        cell.describeLabel.accessibilityLabel = "發布日 \(dateString)。\(epidemic.description)"
        cell.selectionStyle = .none
        return cell
    }
    

    /*
    // Override to support conditional editing of the table view.
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }
    */

    /*
    // Override to support editing the table view.
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            // Delete the row from the data source
            tableView.deleteRows(at: [indexPath], with: .fade)
        } else if editingStyle == .insert {
            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
        }    
    }
    */

    /*
    // Override to support rearranging the table view.
    override func tableView(_ tableView: UITableView, moveRowAt fromIndexPath: IndexPath, to: IndexPath) {

    }
    */

    /*
    // Override to support conditional rearranging of the table view.
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the item to be re-orderable.
        return true
    }
    */

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
