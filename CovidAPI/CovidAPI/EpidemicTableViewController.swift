//
//  EpidemicTableViewController.swift
//  CovidAPI
//  Created by 鄭淳澧 on 2021/5/31.
//

import UIKit

struct Epidemic: Codable {
    var headline: String
    var effective: Date
    var description: String
}


class EpidemicTableViewCell: UITableViewCell {

    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var ourbreakDayLabel: UILabel!
    
}


class EpidemicTableViewController: UITableViewController {
    var epidemics: [Epidemic] = []
    
    var refreshCon: UIRefreshControl!



   
    @IBSegueAction func showDetail(_ coder: NSCoder) -> DetailViewController? {
        let controller =  DetailViewController(coder: coder)
              if let row = tableView.indexPathForSelectedRow?.row {
                  controller?.epidemic = epidemics[row]
                  
              }
              return controller
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        getInfo()

        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always

        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 88

        refreshCon = UIRefreshControl()
        refreshCon.addTarget(self, action: #selector(refresh), for: .valueChanged)
        tableView.refreshControl = refreshCon
    }
    
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        // #warning Incomplete implementation, return the number of sections
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        return epidemics.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "outBreakCell", for: indexPath) as! EpidemicTableViewCell
        let epidemic = epidemics[indexPath.row]

        let symbolConfig = UIImage.SymbolConfiguration(textStyle: .headline)
        let icon = UIImage(systemName: "exclamationmark.triangle.fill", withConfiguration: symbolConfig)?
            .withTintColor(.systemOrange, renderingMode: .alwaysOriginal)
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

    
    func getInfo() {
        let urlStr = "https://www.cdc.gov.tw/TravelEpidemic/ExportJSON"

        if let url = URL(string: urlStr) {
            URLSession.shared.dataTask(with: url) { (data, response, error) in
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let data = data {
                    do {
                        let epdemic = try decoder.decode([Epidemic].self, from: data)
                        self.epidemics = epdemic
                    } catch {
                        print(error)
                    }
                }
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                    self.refreshCon?.endRefreshing()
                }
            }.resume()

        } else {
            print("Invalid URL.")
        }
    }


    @objc func refresh() {
        getInfo()
    }
    
    
}

