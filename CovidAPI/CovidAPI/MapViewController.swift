//
//  MapViewController.swift
//  CovidAPI
//

import UIKit
import MapKit

enum AlertLevel {
    case watch    // 第一級 注意
    case alert    // 第二級 警示
    case warning  // 第三級 警告
    case unknown

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
        case .watch:   return .systemYellow
        case .alert:   return .systemOrange
        case .warning: return .systemRed
        case .unknown: return .systemGray
        }
    }

    var label: String {
        switch self {
        case .watch:   return "第一級 注意"
        case .alert:   return "第二級 警示"
        case .warning: return "第三級 警告"
        case .unknown: return "未分類"
        }
    }
}

class EpidemicAnnotation: NSObject, MKAnnotation {
    let epidemic: Epidemic
    let coordinate: CLLocationCoordinate2D

    init(epidemic: Epidemic, coordinate: CLLocationCoordinate2D) {
        self.epidemic = epidemic
        self.coordinate = coordinate
    }

    var title: String? { epidemic.headline }

    var subtitle: String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return "\(alertLevel.label)・\(formatter.string(from: epidemic.effective))"
    }

    var alertLevel: AlertLevel {
        AlertLevel.from(epidemic: epidemic)
    }
}

class MapViewController: UIViewController {

    let mapView = MKMapView()
    var epidemics: [Epidemic] = []

    override func loadView() {
        view = mapView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "疫情警告地圖"
        navigationItem.largeTitleDisplayMode = .always

        mapView.delegate = self
        mapView.showsCompass = true

        let center = CLLocationCoordinate2D(latitude: 23.5, longitude: 121.0)
        let span = MKCoordinateSpan(latitudeDelta: 80, longitudeDelta: 80)
        mapView.setRegion(MKCoordinateRegion(center: center, span: span), animated: false)

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .refresh,
            target: self,
            action: #selector(reload)
        )

        getInfo()
    }

    @objc func reload() {
        mapView.removeAnnotations(mapView.annotations)
        getInfo()
    }

    func getInfo() {
        let urlStr = "https://www.cdc.gov.tw/TravelEpidemic/ExportJSON"
        guard let url = URL(string: urlStr) else { return }

        URLSession.shared.dataTask(with: url) { [weak self] (data, _, _) in
            guard let self = self, let data = data else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let list = try? decoder.decode([Epidemic].self, from: data) else { return }
            self.epidemics = list
            DispatchQueue.main.async {
                self.geocodeNext(index: 0)
            }
        }.resume()
    }

    private func geocodeNext(index: Int) {
        guard index < epidemics.count else { return }
        let epidemic = epidemics[index]

        CLGeocoder().geocodeAddressString(epidemic.headline) { [weak self] (placemarks, _) in
            guard let self = self else { return }
            if let coord = placemarks?.first?.location?.coordinate {
                let annotation = EpidemicAnnotation(epidemic: epidemic, coordinate: coord)
                self.mapView.addAnnotation(annotation)
            }
            // CLGeocoder 有 rate limit，每筆隔 0.3 秒再送下一筆
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.geocodeNext(index: index + 1)
            }
        }
    }
}

extension MapViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let epAnn = annotation as? EpidemicAnnotation else { return nil }
        let id = "EpidemicMarker"
        let view: MKMarkerAnnotationView
        if let dequeued = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView {
            dequeued.annotation = annotation
            view = dequeued
        } else {
            view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
        }
        view.markerTintColor = epAnn.alertLevel.color
        view.glyphImage = UIImage(systemName: "exclamationmark")
        view.canShowCallout = true
        return view
    }
}
