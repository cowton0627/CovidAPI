//
//  MapViewController.swift
//  CovidAPI
//

import UIKit
import MapKit
import CoreLocation

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

    var glyphText: String {
        switch self {
        case .watch:   return "1"
        case .alert:   return "2"
        case .warning: return "3"
        case .unknown: return "?"
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

    var alertLevel: AlertLevel {
        AlertLevel.from(epidemic: epidemic)
    }
}

class MapViewController: UIViewController {

    let mapView = MKMapView()
    let locationManager = CLLocationManager()
    var epidemics: [Epidemic] = []
    private var hasCenteredOnUser = false

    override func loadView() {
        view = mapView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "疫情警告地圖"
        navigationItem.largeTitleDisplayMode = .always

        mapView.delegate = self
        mapView.showsCompass = true
        mapView.showsUserLocation = true

        let center = CLLocationCoordinate2D(latitude: 23.5, longitude: 121.0)
        let span = MKCoordinateSpan(latitudeDelta: 80, longitudeDelta: 80)
        mapView.setRegion(MKCoordinateRegion(center: center, span: span), animated: false)

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .refresh,
            target: self,
            action: #selector(reload)
        )

        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()

        getInfo()
    }

    @objc func reload() {
        let epidemicAnnotations = mapView.annotations.filter { $0 is EpidemicAnnotation }
        mapView.removeAnnotations(epidemicAnnotations)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.geocodeNext(index: index + 1)
            }
        }
    }

    private func makeCalloutDetailView(for ann: EpidemicAnnotation) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        let levelLabel = UILabel()
        levelLabel.text = ann.alertLevel.label
        levelLabel.font = .preferredFont(forTextStyle: .headline)
        levelLabel.textColor = ann.alertLevel.color
        levelLabel.adjustsFontForContentSizeCategory = true

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        let dateLabel = UILabel()
        dateLabel.text = "發布日：\(formatter.string(from: ann.epidemic.effective))"
        dateLabel.font = .preferredFont(forTextStyle: .subheadline)
        dateLabel.textColor = .secondaryLabel
        dateLabel.adjustsFontForContentSizeCategory = true

        let descLabel = UILabel()
        descLabel.text = String(ann.epidemic.description.prefix(120))
        descLabel.font = .preferredFont(forTextStyle: .footnote)
        descLabel.textColor = .label
        descLabel.numberOfLines = 4
        descLabel.adjustsFontForContentSizeCategory = true

        stack.addArrangedSubview(levelLabel)
        stack.addArrangedSubview(dateLabel)
        stack.addArrangedSubview(descLabel)

        descLabel.widthAnchor.constraint(equalToConstant: 240).isActive = true
        return stack
    }
}

extension MapViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation { return nil }
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
        view.glyphText = epAnn.alertLevel.glyphText
        view.canShowCallout = true
        view.detailCalloutAccessoryView = makeCalloutDetailView(for: epAnn)
        view.rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
        return view
    }

    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
        guard let ann = view.annotation as? EpidemicAnnotation else { return }
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let detail = storyboard.instantiateViewController(withIdentifier: "DetailViewController") as? DetailViewController else { return }
        detail.epidemic = ann.epidemic
        navigationController?.pushViewController(detail, animated: true)
    }
}

extension MapViewController: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !hasCenteredOnUser, let loc = locations.last else { return }
        hasCenteredOnUser = true
        let region = MKCoordinateRegion(
            center: loc.coordinate,
            latitudinalMeters: 2_000_000,
            longitudinalMeters: 2_000_000
        )
        mapView.setRegion(region, animated: true)
        manager.stopUpdatingLocation()
    }
}
