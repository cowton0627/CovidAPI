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
    private let favoriteStore: FavoriteStoreProtocol = FavoriteStore.shared
    private let coordinateCache: CoordinateCacheProtocol = CoordinateCache()
    private let geocoder = CLGeocoder()
    var epidemics: [Epidemic] = []
    private var allEpidemics: [Epidemic] = []
    private var selectedFilter: AlertFilter = .all
    private var showsFavoritesOnly = false
    private var hasCenteredOnUser = false
    private var geocodingGeneration = 0
    private let statusLabel = UILabel()
    private let filterControl = UISegmentedControl(items: AlertFilter.allCases.map(\.title))
    private lazy var fitAllButton = UIBarButtonItem(
        image: UIImage(systemName: "globe.asia.australia"),
        style: .plain,
        target: self,
        action: #selector(showAllAnnotations)
    )
    private var pendingFocusIdentifier: String?

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

        let refreshButton = UIBarButtonItem(
            barButtonSystemItem: .refresh,
            target: self,
            action: #selector(reload)
        )
        refreshButton.accessibilityLabel = "重新整理疫情地圖"
        fitAllButton.accessibilityIdentifier = "epidemic.map.showAll"
        fitAllButton.accessibilityLabel = "顯示全部疫情標記"
        fitAllButton.isEnabled = false
        navigationItem.rightBarButtonItems = [refreshButton, fitAllButton]
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "star"),
            menu: makeFavoritesMenu()
        )
        navigationItem.leftBarButtonItem?.accessibilityIdentifier = "epidemic.map.favorites"
        updateFavoritesMenu()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(favoritesDidChange),
            name: .epidemicFavoritesDidChange,
            object: nil
        )

        if !isUITesting {
            locationManager.delegate = self
            locationManager.requestWhenInUseAuthorization()
        }

        configureFilterControl()
        configureStatusLabel()
        loadData()
    }

    @objc func reload() {
        let epidemicAnnotations = mapView.annotations.filter { $0 is EpidemicAnnotation }
        mapView.removeAnnotations(epidemicAnnotations)
        loadData(forceRefresh: true)
    }

    @objc private func showAllAnnotations() {
        let annotations = mapView.annotations.compactMap { $0 as? EpidemicAnnotation }
        guard !annotations.isEmpty else { return }
        pendingFocusIdentifier = nil
        if annotations.count == 1, let annotation = annotations.first {
            let region = MKCoordinateRegion(
                center: annotation.coordinate,
                latitudinalMeters: 3_000_000,
                longitudinalMeters: 3_000_000
            )
            mapView.setRegion(region, animated: true)
            return
        }
        let mapRect = annotations.reduce(MKMapRect.null) { result, annotation in
            let point = MKMapPoint(annotation.coordinate)
            return result.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        mapView.setVisibleMapRect(
            mapRect,
            edgePadding: UIEdgeInsets(top: 64, left: 32, bottom: 32, right: 32),
            animated: true
        )
    }

    func focus(on epidemic: Epidemic) {
        loadViewIfNeeded()
        pendingFocusIdentifier = epidemic.notificationIdentifier
        selectedFilter = .all
        showsFavoritesOnly = false
        filterControl.selectedSegmentIndex = AlertFilter.all.rawValue
        updateFavoritesMenu()
        if !allEpidemics.isEmpty {
            applyFilter()
        }
        focusPendingAnnotationIfAvailable()
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
        allEpidemics = snapshot.epidemics
        updateFilterAvailability()
        applyFilter()
    }

    private func applyFilter() {
        geocodingGeneration += 1
        geocoder.cancelGeocode()
        let annotations = mapView.annotations.filter { $0 is EpidemicAnnotation }
        mapView.removeAnnotations(annotations)
        fitAllButton.isEnabled = false
        epidemics = allEpidemics.filter {
            selectedFilter.matches($0) && (!showsFavoritesOnly || favoriteStore.contains($0))
        }
        guard !epidemics.isEmpty else {
            statusLabel.text = showsFavoritesOnly
                ? "沒有符合此等級的收藏地區疫情"
                : "沒有符合此等級的疫情資料"
            statusLabel.isHidden = false
            return
        }
        statusLabel.isHidden = true
        geocodeNext(index: 0, generation: geocodingGeneration)
    }

    private func configureFilterControl() {
        filterControl.selectedSegmentIndex = selectedFilter.rawValue
        filterControl.selectedSegmentTintColor = .systemOrange
        filterControl.accessibilityIdentifier = "epidemic.map.filter"
        filterControl.addTarget(self, action: #selector(filterChanged), for: .valueChanged)
        filterControl.translatesAutoresizingMaskIntoConstraints = false
        mapView.addSubview(filterControl)
        NSLayoutConstraint.activate([
            filterControl.leadingAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            filterControl.trailingAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            filterControl.topAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.topAnchor, constant: 8),
            filterControl.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    private func updateFilterAvailability() {
        for filter in AlertFilter.allCases where filter != .all {
            filterControl.setEnabled(allEpidemics.contains(where: filter.matches), forSegmentAt: filter.rawValue)
        }
    }

    @objc private func filterChanged() {
        guard let filter = AlertFilter(rawValue: filterControl.selectedSegmentIndex) else { return }
        selectedFilter = filter
        applyFilter()
    }

    @objc private func favoritesDidChange() {
        if showsFavoritesOnly {
            applyFilter()
        }
        updateFavoritesMenu()
    }

    private func toggleFavoritesFilter() {
        showsFavoritesOnly.toggle()
        updateFavoritesMenu()
        applyFilter()
    }

    private func updateFavoritesMenu() {
        navigationItem.leftBarButtonItem?.image = UIImage(
            systemName: showsFavoritesOnly ? "star.fill" : "star"
        )
        navigationItem.leftBarButtonItem?.accessibilityLabel = "地圖收藏與篩選"
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
            guard let self = self else { return }
            let controller = FavoritesViewController(epidemics: self.allEpidemics)
            self.navigationController?.pushViewController(controller, animated: true)
        }
        return UIMenu(children: [filter, manage])
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
            statusLabel.topAnchor.constraint(equalTo: filterControl.bottomAnchor, constant: 12),
            statusLabel.widthAnchor.constraint(lessThanOrEqualTo: mapView.widthAnchor, multiplier: 0.8),
            statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }

    private func geocodeNext(index: Int, generation: Int) {
        guard generation == geocodingGeneration, index < epidemics.count else { return }
        let epidemic = epidemics[index]
        let locationName = LocationNameNormalizer.normalize(epidemic.headline)

        if let coordinate = uiTestingCoordinate(for: locationName) {
            addAnnotation(for: epidemic, coordinate: coordinate)
            geocodeNext(index: index + 1, generation: generation)
            return
        }

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
        let annotation = EpidemicAnnotation(epidemic: epidemic, coordinate: coordinate)
        mapView.addAnnotation(annotation)
        fitAllButton.isEnabled = true
        focusPendingAnnotationIfAvailable()
    }

    private func focusPendingAnnotationIfAvailable() {
        guard let identifier = pendingFocusIdentifier,
              let annotation = mapView.annotations.compactMap({ $0 as? EpidemicAnnotation }).first(where: {
                  $0.epidemic.notificationIdentifier == identifier
              }) else { return }
        let region = MKCoordinateRegion(
            center: annotation.coordinate,
            latitudinalMeters: 3_000_000,
            longitudinalMeters: 3_000_000
        )
        mapView.setRegion(region, animated: false)
    }

    private func selectPendingAnnotationIfAvailable() {
        guard let identifier = pendingFocusIdentifier,
              let annotation = mapView.annotations.compactMap({ $0 as? EpidemicAnnotation }).first(where: {
                  $0.epidemic.notificationIdentifier == identifier
              }) else { return }
        pendingFocusIdentifier = nil
        mapView.selectAnnotation(annotation, animated: true)
    }

    private func uiTestingCoordinate(for locationName: String) -> CLLocationCoordinate2D? {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return nil }
        switch locationName {
        case "日本": return CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
        case "美國": return CLLocationCoordinate2D(latitude: 37.0902, longitude: -95.7129)
        default: return nil
        }
    }

    private func makeCalloutDetailView(for ann: EpidemicAnnotation) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        let levelLabel = UILabel()
        levelLabel.accessibilityIdentifier = "epidemic.map.callout.level"
        levelLabel.text = ann.alertLevel.label
        levelLabel.font = .preferredFont(forTextStyle: .headline)
        levelLabel.textColor = ann.alertLevel.color
        levelLabel.adjustsFontForContentSizeCategory = true

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        let dateLabel = UILabel()
        dateLabel.accessibilityIdentifier = "epidemic.map.callout.date"
        dateLabel.text = "發布日：\(formatter.string(from: ann.epidemic.effective))"
        dateLabel.font = .preferredFont(forTextStyle: .subheadline)
        dateLabel.textColor = .secondaryLabel
        dateLabel.adjustsFontForContentSizeCategory = true

        let descLabel = UILabel()
        descLabel.accessibilityIdentifier = "epidemic.map.callout.description"
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
    func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
        guard fullyRendered else { return }
        selectPendingAnnotationIfAvailable()
    }

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
        let locationName = LocationNameNormalizer.normalize(epAnn.epidemic.headline)
        view.accessibilityIdentifier = "epidemic.map.marker.\(locationName)"
        view.accessibilityHint = "點兩下顯示摘要與詳細資訊按鈕"
        view.rightCalloutAccessoryView?.accessibilityLabel = "查看完整疫情資訊"
        view.rightCalloutAccessoryView?.accessibilityIdentifier = "epidemic.map.callout.detail"
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
