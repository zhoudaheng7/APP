import SwiftUI
import MapKit
import CoreLocation
import Observation

@MainActor @Observable final class LifeLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    weak var store: LifeStore?
    private(set) var coordinate: CLLocationCoordinate2D?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    var error: String?
    private var foreground = true
    private var lastRecorded: CLLocation?
    private var wantsRoute = false
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyBest; manager.distanceFilter = 10; authorization = manager.authorizationStatus }
    func locate() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        else if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { manager.requestLocation() }
        else { error = "定位尚未开启。可以在 iPhone 设置中允许定位，也可以直接记录地图中心。" }
    }
    func startRoute() {
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { error = "请先在 iPhone 设置中允许使用期间定位。"; return }
        wantsRoute = true
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() } else { beginAuthorizedRoute() }
    }
    private func beginAuthorizedRoute() {
        guard wantsRoute, let store, store.runningRoute != nil || store.startRoute() else { return }
        lastRecorded = nil; if foreground { manager.startUpdatingLocation() }
    }
    func stopRoute() { wantsRoute = false; manager.stopUpdatingLocation(); store?.stopRoute(); lastRecorded = nil }
    func setForeground(_ active: Bool) {
        foreground = active
        if active && wantsRoute && store?.runningRoute != nil { manager.startUpdatingLocation() } else { manager.stopUpdatingLocation() }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if authorization == .authorizedWhenInUse || authorization == .authorizedAlways {
            if wantsRoute { beginAuthorizedRoute() } else { manager.requestLocation() }
        } else if authorization == .denied || authorization == .restricted {
            manager.stopUpdatingLocation(); wantsRoute = false
            if store?.runningRoute != nil { store?.stopRoute() }
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last, fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 100,
              abs(fix.timestamp.timeIntervalSinceNow) < 30 else { return }
        coordinate = fix.coordinate
        guard foreground && wantsRoute && store?.runningRoute != nil else { return }
        if let lastRecorded, fix.distance(from: lastRecorded) < 10 || fix.timestamp.timeIntervalSince(lastRecorded.timestamp) < 5 { return }
        self.lastRecorded = fix
        store?.appendRoutePoint(RoutePoint(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude, at: fix.timestamp))
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { self.error = "暂时无法取得位置，请在信号更好的地方重试。" }
}

struct PlacesView: View {
    @Environment(LifeStore.self) private var store
    @Environment(LifeLocation.self) private var location
    @State private var camera: MapCameraPosition = .automatic
    @State private var center: CLLocationCoordinate2D?
    @State private var adding = false
    @State private var placeName = ""
    @State private var note = ""
    @State private var search = ""
    @State private var searching = false
    @State private var searchError: String?
    @State private var showRouteConsent = false
    @State private var deletePlace: LifePlace?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Map(position: $camera) {
                    UserAnnotation()
                    ForEach(store.data.places) { place in
                        Annotation(place.title, coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)) {
                            Image(systemName: "mappin.circle.fill").font(.title).symbolRenderingMode(.palette).foregroundStyle(.white, .teal)
                        }
                    }
                    if let route = store.runningRoute, route.points.count > 1 {
                        MapPolyline(coordinates: route.points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }).stroke(.teal, lineWidth: 5)
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .mapControls { MapCompass(); MapScaleView() }
                .onMapCameraChange(frequency: .onEnd) { center = $0.region.center }
                .frame(height: 350).clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(alignment: .center) { Image(systemName: "plus").font(.title3).foregroundStyle(.primary).allowsHitTesting(false).accessibilityHidden(true) }
                .overlay(alignment: .bottomTrailing) {
                    Button { location.locate() } label: { Image(systemName: "location.fill").padding(13) }.modifier(MapGlassButton()).padding(12).accessibilityLabel("定位到我")
                }
                HStack(spacing: 10) { TextField("搜索城市、街道或地点", text: $search).textFieldStyle(.roundedBorder).submitLabel(.search).onSubmit { searchPlace() }; Button(action: searchPlace) { if searching { ProgressView() } else { Image(systemName: "magnifyingglass") } }.disabled(searching || search.trimmingCharacters(in: .whitespaces).isEmpty).accessibilityLabel("搜索地点") }
                if let searchError { Text(searchError).font(.caption).foregroundStyle(.secondary) }
                PrimaryAction(title: "记住地图中心的这里", symbol: "mappin.and.ellipse") { if center != nil { adding = true } }
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Label(store.runningRoute == nil ? "走一段自己的路" : "前台路线记录中", systemImage: "figure.walk").font(.headline); Spacer(); if let route = store.runningRoute { Text(route.start, style: .timer).monospacedDigit().font(.subheadline) } }
                    Text("主动开始与结束。切到后台或锁屏时暂停采集，精确位置只保存在本机。") .font(.caption).foregroundStyle(.secondary)
                    if store.runningRoute != nil { Button("结束并保存路线", systemImage: "stop.circle") { location.stopRoute() }.buttonStyle(.bordered) }
                    else { Button("开始前台路线", systemImage: "play.circle") { showRouteConsent = true }.buttonStyle(.bordered) }
                }.padding().frame(maxWidth: .infinity, alignment: .leading).background(Color.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
                Text("记住的地方").font(.title3.bold())
                if store.data.places.isEmpty { ContentUnavailableView("让地图慢慢有故事", systemImage: "mappin.and.ellipse", description: Text("移动地图，记住一处你想留下的地方。")) }
                ForEach(store.data.places) { place in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack { Button(place.title) { camera = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude), span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))) }.font(.headline); Spacer(); Button(role: .destructive) { deletePlace = place } label: { Image(systemName: "trash") }.accessibilityLabel("删除地点\(place.title)") }
                        if !place.note.isEmpty { Text(place.note).font(.subheadline) }
                        Text(place.occurredAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }.padding().frame(maxWidth: .infinity, alignment: .leading).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                }
            }.padding()
        }.background(Color(.systemGroupedBackground)).navigationTitle("地图")
            .onAppear {
                if let place = store.data.places.first { camera = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude), span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))) }
                else if center == nil { camera = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 35, longitude: 105), span: MKCoordinateSpan(latitudeDelta: 45, longitudeDelta: 60))) }
            }
            .onChange(of: location.coordinate?.latitude) { _, _ in if let coordinate = location.coordinate { camera = .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))); center = coordinate } }
            .alert("位置暂不可用", isPresented: Binding(get: { location.error != nil }, set: { if !$0 { location.error = nil } })) { Button("知道了") { location.error = nil } } message: { Text(location.error ?? "") }
            .alert("开始记录前台路线？", isPresented: $showRouteConsent) { Button("开始记录") { location.startRoute() }; Button("取消", role: .cancel) {} } message: { Text("仅在 LifeOS 前台打开时记录位置。后台和锁屏期间不会补画路线，也不会自动确认活动或成果。") }
            .confirmationDialog("删除这个地点记忆？", isPresented: Binding(get: { deletePlace != nil }, set: { if !$0 { deletePlace = nil } }), titleVisibility: .visible) { Button("删除", role: .destructive) { if let p = deletePlace { store.deletePlace(p) }; deletePlace = nil }; Button("取消", role: .cancel) {} }
            .sheet(isPresented: $adding) {
                NavigationStack { Form { Section { TextField("这个地方叫什么？", text: $placeName); TextField("留下当时的心情或故事", text: $note, axis: .vertical).lineLimit(4...8) }; Section { Text("这是你手动留下的地点记忆，不代表自动检测到到访。") .font(.caption).foregroundStyle(.secondary) } }.navigationTitle("记住这里").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { adding = false } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { if let c = center, store.addPlace(LifePlace(title: placeName.trimmingCharacters(in: .whitespacesAndNewlines), note: note, latitude: c.latitude, longitude: c.longitude)) { adding = false; placeName = ""; note = "" } }.disabled(placeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } } }
            }
    }
    func searchPlace() {
        guard !searching && !search.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        searching = true; searchError = nil
        let request = MKLocalSearch.Request(); request.naturalLanguageQuery = search
        Task { @MainActor in
            defer { searching = false }
            do {
                let response = try await MKLocalSearch(request: request).start()
                guard let item = response.mapItems.first else { searchError = "没有找到，试试更完整的地址。"; return }
                center = item.placemark.coordinate
                camera = .region(MKCoordinateRegion(center: item.placemark.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
            } catch { searchError = "搜索暂不可用，也可以直接移动地图。" }
        }
    }
}

struct MapGlassButton: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26, *) { content.buttonStyle(.glass).buttonBorderShape(.circle) }
        else { content.background(.regularMaterial, in: Circle()) }
    }
}

struct RouteDetailView: View {
    @Environment(LifeStore.self) private var store
    var routeID: UUID
    var body: some View {
        if let route = store.data.routes.first(where: { $0.id == routeID }) {
            ScrollView { VStack(alignment: .leading, spacing: 18) {
                Map { if route.points.count > 1 { MapPolyline(coordinates: route.points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }).stroke(.teal, lineWidth: 5) }; if let first = route.points.first { Marker("起点", coordinate: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)).tint(.teal) }; if let last = route.points.last { Marker(route.end == nil ? "最近位置" : "终点", coordinate: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)).tint(.orange) } }.frame(height: 400).clipShape(RoundedRectangle(cornerRadius: 24))
                Text(route.title).font(.title2.bold()); Text(route.start.formatted(date: .complete, time: .shortened)).foregroundStyle(.secondary)
                Text("\(route.points.count) 个前台采样点").font(.subheadline)
                Text("采样只发生在你主动开启且 App 前台打开时；缺失片段不自动补成经过的路线。") .font(.caption).foregroundStyle(.secondary)
            }.padding() }.navigationTitle("沿途").navigationBarTitleDisplayMode(.inline)
        }
    }
}
