//
//  MapViewController.swift
//  CovidAPI
//

import UIKit
import MapKit
import CoreLocation

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
    private let repository = EpidemicRepository.shared
    private let coordinateCache: CoordinateCacheProtocol = CoordinateCache()
    private let geocoder = CLGeocoder()
    var epidemics: [Epidemic] = []
    private var hasCenteredOnUser = false
    private var geocodingGeneration = 0
    private let statusLabel = UILabel()

    override func loadView() {
        view = mapView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "疫情警告地圖"
        navigationItem.largeTitleDisplayMode = .always

        mapView.delegate = self
        mapView.accessibilityIdentifier = "epidemic.map"
        mapView.showsCompass = true
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        mapView.showsUserLocation = !isUITesting

        let center = CLLocationCoordinate2D(latitude: 23.5, longitude: 121.0)
        let span = MKCoordinateSpan(latitudeDelta: 80, longitudeDelta: 80)
        mapView.setRegion(MKCoordinateRegion(center: center, span: span), animated: false)

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .refresh,
            target: self,
            action: #selector(reload)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "重新整理疫情地圖"

        if !isUITesting {
            locationManager.delegate = self
            locationManager.requestWhenInUseAuthorization()
        }

        configureStatusLabel()
        loadData()
    }

    @objc func reload() {
        let epidemicAnnotations = mapView.annotations.filter { $0 is EpidemicAnnotation }
        mapView.removeAnnotations(epidemicAnnotations)
        loadData(forceRefresh: true)
    }

    private func loadData(forceRefresh: Bool = false) {
        statusLabel.text = "正在載入地圖資料…"
        statusLabel.isHidden = false

        if !forceRefresh, let snapshot = repository.cachedSnapshot() {
            show(snapshot)
        }

        repository.refresh { [weak self] result in
            switch result {
            case .success(let snapshot):
                self?.show(snapshot)
            case .failure(let error):
                self?.statusLabel.text = error.localizedDescription + "\n點右上角重新整理"
            }
        }
    }

    private func show(_ snapshot: EpidemicSnapshot) {
        geocodingGeneration += 1
        geocoder.cancelGeocode()
        let annotations = mapView.annotations.filter { $0 is EpidemicAnnotation }
        mapView.removeAnnotations(annotations)
        epidemics = snapshot.epidemics
        statusLabel.isHidden = true
        geocodeNext(index: 0, generation: geocodingGeneration)
    }

    private func configureStatusLabel() {
        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.textColor = .secondaryLabel
        statusLabel.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.9)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.layer.cornerRadius = 10
        statusLabel.layer.masksToBounds = true
        statusLabel.accessibilityIdentifier = "epidemic.map.status"
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        mapView.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: mapView.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.topAnchor, constant: 12),
            statusLabel.widthAnchor.constraint(lessThanOrEqualTo: mapView.widthAnchor, multiplier: 0.8),
            statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }

    private func geocodeNext(index: Int, generation: Int) {
        guard generation == geocodingGeneration, index < epidemics.count else { return }
        let epidemic = epidemics[index]
        let locationName = LocationNameNormalizer.normalize(epidemic.headline)

        if let coordinate = coordinateCache.coordinate(for: locationName) {
            addAnnotation(for: epidemic, coordinate: coordinate)
            geocodeNext(index: index + 1, generation: generation)
            return
        }

        geocoder.geocodeAddressString(locationName) { [weak self] placemarks, _ in
            guard let self = self, generation == self.geocodingGeneration else { return }
            if let coord = placemarks?.first?.location?.coordinate {
                self.coordinateCache.save(coord, for: locationName)
                self.addAnnotation(for: epidemic, coordinate: coord)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.geocodeNext(index: index + 1, generation: generation)
            }
        }
    }

    private func addAnnotation(for epidemic: Epidemic, coordinate: CLLocationCoordinate2D) {
        mapView.addAnnotation(EpidemicAnnotation(epidemic: epidemic, coordinate: coordinate))
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
        if let cluster = annotation as? MKClusterAnnotation {
            let id = "EpidemicCluster"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: cluster, reuseIdentifier: id)
            view.annotation = cluster
            view.markerTintColor = .systemIndigo
            view.glyphText = String(cluster.memberAnnotations.count)
            view.titleVisibility = .hidden
            view.subtitleVisibility = .hidden
            view.accessibilityLabel = "疫情警告群組，共 \(cluster.memberAnnotations.count) 筆"
            return view
        }
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
        view.clusteringIdentifier = "epidemic"
        view.displayPriority = .defaultHigh
        view.canShowCallout = true
        view.detailCalloutAccessoryView = makeCalloutDetailView(for: epAnn)
        view.rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
        view.accessibilityLabel = "\(epAnn.epidemic.headline)，\(epAnn.alertLevel.label)"
        view.accessibilityHint = "點兩下顯示摘要與詳細資訊按鈕"
        view.rightCalloutAccessoryView?.accessibilityLabel = "查看完整疫情資訊"
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
        case .denied, .restricted:
            statusLabel.text = "未開啟定位，仍可瀏覽全球疫情警告。"
            statusLabel.isHidden = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.statusLabel.isHidden = true
            }
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
