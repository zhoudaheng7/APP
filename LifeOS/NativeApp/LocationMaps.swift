import SwiftUI
import MapKit
import CoreLocation
import Observation

@MainActor @Observable final class LifeLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    weak var store: LifeStore?
    private(set) var coordinate: CLLocationCoordinate2D?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var precise = false
    private(set) var visitStatus = "自动到访未开启"
    var error: String?
    private var foreground = true
    private var lastRecorded: CLLocation?
    private var wantsRoute = false
    private var wantsFix = false
    private var backgroundRoute = false
    private var routeSegment = 0
    var isRecording: Bool { wantsRoute && store?.runningRoute != nil }
    var visitOptIn: Bool { UserDefaults.standard.bool(forKey: "dayisle.visits.enabled") }
    override init() {
        super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 15; manager.activityType = .otherNavigation; manager.pausesLocationUpdatesAutomatically = true
        authorization = manager.authorizationStatus; precise = manager.accuracyAuthorization == .fullAccuracy
    }
    func attach(_ store: LifeStore) {
        guard self.store == nil else { return }; self.store = store
        if store.runningRoute != nil { store.routeGap("App重新打开，路线等待你确认继续") }
        updateVisits()
    }
    func enableVisits() {
        guard CLLocationManager.locationServicesEnabled() else { error = "系统定位已关闭，请先在设置中开启。"; return }
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization(); visitStatus = "请先允许使用期间定位，再点击开启自动到访。"; return
        }
        guard manager.authorizationStatus == .authorizedAlways else {
            if manager.authorizationStatus == .authorizedWhenInUse { manager.requestAlwaysAuthorization() }
            visitStatus = "自动到访需要“始终”定位。授权后再点击开启；也可仅使用手动地点。"; return
        }
        guard store?.setVisitCollection(true) == true else { return }
        UserDefaults.standard.set(true, forKey: "dayisle.visits.enabled"); updateVisits()
    }
    func disableVisits() {
        guard store?.setVisitCollection(false) == true else { return }
        UserDefaults.standard.set(false, forKey: "dayisle.visits.enabled"); manager.stopMonitoringVisits(); visitStatus = "已暂停；已有记录保留，新的到访不再接收。"
    }
    func pauseAfterRestore() {
        wantsRoute = false; wantsFix = false; lastRecorded = nil; manager.stopUpdatingLocation(); manager.allowsBackgroundLocationUpdates = false
        manager.stopMonitoringVisits(); UserDefaults.standard.set(false, forKey: "dayisle.visits.enabled"); visitStatus = "备份已恢复，自动到访暂停；请按需要重新开启。"
    }
    private func updateVisits() {
        guard visitOptIn, store?.ready == true else { manager.stopMonitoringVisits(); return }
        guard manager.authorizationStatus == .authorizedAlways else {
            manager.stopMonitoringVisits(); _ = store?.setVisitCollection(false)
            visitStatus = "定位权限变化，自动到访已暂停；重新允许后请主动开启。"; UserDefaults.standard.set(false, forKey: "dayisle.visits.enabled"); return
        }
        guard store?.setVisitCollection(true) == true else { return }
        manager.startMonitoringVisits(); visitStatus = "低功耗到访已开启 · 系统可能延迟送达，先存为待核对"
    }
    func locate() {
        wantsFix = true
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        else if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { manager.requestLocation() }
        else { error = "定位尚未开启。可以在 iPhone 设置中允许定位，也可以直接记录地图中心。" }
    }
    func startRoute(background: Bool = false) {
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { error = "请先在 iPhone 设置中允许使用期间定位。"; return }
        wantsRoute = true; backgroundRoute = background
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() } else { beginAuthorizedRoute() }
    }
    private func beginAuthorizedRoute() {
        guard wantsRoute, foreground, let store, store.beginRoute(background: backgroundRoute) else { return }
        lastRecorded = nil
        routeSegment = max(routeSegment, store.runningRoute?.points.map(\.segment).max() ?? 0) + 1
        manager.allowsBackgroundLocationUpdates = backgroundRoute; manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }
    func stopRoute() { wantsRoute = false; manager.stopUpdatingLocation(); manager.allowsBackgroundLocationUpdates = false; store?.stopRoute(); lastRecorded = nil }
    func setForeground(_ active: Bool) {
        if foreground != active && wantsRoute && !backgroundRoute {
            routeSegment += 1; lastRecorded = nil
            if !active { store?.routeGap("仅前台模式：锁屏或离开App") }
        }
        foreground = active
        if wantsRoute && store?.runningRoute != nil && (active || backgroundRoute) { manager.startUpdatingLocation() } else { manager.stopUpdatingLocation() }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus; precise = manager.accuracyAuthorization == .fullAccuracy
        if authorization == .authorizedWhenInUse || authorization == .authorizedAlways {
            if wantsRoute { beginAuthorizedRoute() } else if wantsFix { manager.requestLocation() }
        } else if authorization == .denied || authorization == .restricted {
            manager.stopUpdatingLocation(); wantsRoute = false
            if store?.runningRoute != nil { store?.routeGap("定位权限已撤销，采样停止") }
        }
        updateVisits()
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last, fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 100,
              abs(fix.timestamp.timeIntervalSinceNow) < 30 else { return }
        coordinate = fix.coordinate
        wantsFix = false
        guard (foreground || backgroundRoute) && wantsRoute, let store, let route = store.runningRoute else { return }
        guard Date().timeIntervalSince(route.start) <= 6 * 3600 else { stopRoute(); error = "本段短路线达到6小时上限，已结束保存。"; return }
        if let previous = route.points.last, fix.timestamp.timeIntervalSince(previous.at) > 120 {
            store.routeGap("采样间隔超过两分钟", at: previous.at); routeSegment += 1
        }
        if let lastRecorded, fix.distance(from: lastRecorded) < 10 || fix.timestamp.timeIntervalSince(lastRecorded.timestamp) < 5 { return }
        self.lastRecorded = fix
        store.appendRoutePoint(RoutePoint(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude, at: fix.timestamp, segment: routeSegment))
    }
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        guard visitOptIn, manager.authorizationStatus == .authorizedAlways else { return }
        _ = store?.receiveVisit(VisitObservation(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude, accuracy: visit.horizontalAccuracy, arrival: visit.arrivalDate == .distantPast ? nil : visit.arrivalDate, departure: visit.departureDate == .distantFuture ? nil : visit.departureDate))
    }
    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) { store?.routeGap("系统暂停了位置采样"); routeSegment += 1; lastRecorded = nil }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if wantsRoute { store?.routeGap("暂时无法取得位置"); routeSegment += 1; lastRecorded = nil }
        self.error = "暂时无法取得位置，缺口已保留。请在信号更好的地方重试。"
    }
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
    @State private var backgroundRoute = false
    @State private var newKnownPlace: KnownPlace?
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
                        ForEach(Array(Set(route.points.map(\.segment))).sorted(), id: \.self) { segment in
                            MapPolyline(coordinates: route.points.filter { $0.segment == segment }.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }).stroke(.teal, lineWidth: 5)
                        }
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
                Button("将地图中心命名为稳定地点", systemImage: "mappin.circle") { if let center { newKnownPlace = KnownPlace(title: "", latitude: center.latitude, longitude: center.longitude) } }
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Label(store.runningRoute == nil ? "走一段自己的路" : location.isRecording ? "短路线记录中" : "上次路线已暂停", systemImage: "figure.walk").font(.headline); Spacer(); if let route = store.runningRoute { Text(route.start.formatted(date: .omitted, time: .shortened)).font(.subheadline) } }
                    Toggle("本段允许锁屏与后台记录", isOn: $backgroundRoute).disabled(location.isRecording)
                    Text("每段最长6小时，最多20,000采样点。后台记录会增加耗电并显示系统位置指示；系统限制、强退或关权限可能中断，缺口不补画。精确位置只存本机。") .font(.caption).foregroundStyle(.secondary)
                    if store.runningRoute != nil {
                        if !location.isRecording { Button("确认继续这段路线", systemImage: "play.circle") { location.startRoute(background: backgroundRoute) }.buttonStyle(.bordered) }
                        Button("结束并保存路线", systemImage: "stop.circle") { location.stopRoute() }.buttonStyle(.bordered)
                    }
                    else { Button("开始一段短路线", systemImage: "play.circle") { showRouteConsent = true }.buttonStyle(.bordered) }
                }.padding().frame(maxWidth: .infinity, alignment: .leading).background(Color.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
                NavigationLink { VisitInboxView() } label: { Label("到访收件箱 · \(store.data.visits.filter { $0.state == "inferred" }.count) 待核对", systemImage: "tray") }
                NavigationLink { MapHistoryView() } label: { Label("按日期回看地图与路线", systemImage: "clock.arrow.circlepath") }
                NavigationLink { KnownPlaceLibrary() } label: { Label("我的稳定地点", systemImage: "mappin.circle") }
                Text("记住的地方").font(.title3.bold())
                if store.data.places.isEmpty { ContentUnavailableView("让地图慢慢有故事", systemImage: "mappin.and.ellipse", description: Text("移动地图，记住一处你想留下的地方。")) }
                ForEach(store.data.places) { place in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack { Button(place.title) { camera = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude), span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))) }.font(.headline); Spacer(); Button(role: .destructive) { deletePlace = place } label: { Image(systemName: "trash") }.accessibilityLabel("删除地点\(place.title)") }
                        if !place.note.isEmpty { Text(place.note).font(.subheadline) }
                        NavigationLink("打开这段记忆") { MemoryDetailView(memoryID: place.id) }
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
            .alert("开始记录这段路线？", isPresented: $showRouteConsent) { Button("开始记录") { location.startRoute(background: backgroundRoute) }; Button("取消", role: .cancel) {} } message: { Text(backgroundRoute ? "本段允许锁屏与后台采样。位置只存本机；不能保证系统中断或强退后继续记录。" : "本段仅前台采样，离开App或锁屏期间会留下缺口。") }
            .confirmationDialog("删除这个地点记忆？", isPresented: Binding(get: { deletePlace != nil }, set: { if !$0 { deletePlace = nil } }), titleVisibility: .visible) { Button("删除", role: .destructive) { if let p = deletePlace { store.deletePlace(p) }; deletePlace = nil }; Button("取消", role: .cancel) {} }
            .sheet(isPresented: $adding) {
                NavigationStack { Form { Section { TextField("这个地方叫什么？", text: $placeName); TextField("留下当时的心情或故事", text: $note, axis: .vertical).lineLimit(4...8) }; Section { Text("这是你手动留下的地点记忆，不代表自动检测到到访。") .font(.caption).foregroundStyle(.secondary) } }.navigationTitle("记住这里").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { adding = false } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { if let c = center, store.addPlace(LifePlace(title: placeName.trimmingCharacters(in: .whitespacesAndNewlines), note: note, latitude: c.latitude, longitude: c.longitude)) { adding = false; placeName = ""; note = "" } }.disabled(placeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } } }
            }
            .sheet(item: $newKnownPlace) { place in NavigationStack { KnownPlaceEditor(place: place) } }
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
    @State private var position = 0.0
    @State private var title = ""
    @State private var note = ""
    @State private var transport = "未知"
    @State private var tripID: UUID?
    @State private var initialized = false
    @State private var delete = false
    var body: some View {
        if let route = store.data.routes.first(where: { $0.id == routeID }) {
            let index = min(max(0, Int(position)), max(0, route.points.count - 1))
            let visible = Array(route.points.prefix(index + 1))
            ScrollView { VStack(alignment: .leading, spacing: 18) {
                Map {
                    ForEach(Array(Set(visible.map(\.segment))).sorted(), id: \.self) { segment in
                        MapPolyline(coordinates: visible.filter { $0.segment == segment }.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }).stroke(.teal, lineWidth: 5)
                    }
                    if let first = route.points.first { Marker("起点", coordinate: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)).tint(.teal) }
                    if let last = visible.last { Marker("当前回看采样", coordinate: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)).tint(.orange) }
                }.frame(height: 400).clipShape(RoundedRectangle(cornerRadius: 24))
                if route.points.count > 1 { Slider(value: $position, in: 0...Double(route.points.count - 1), step: 1) { Text("按真实采样回看") }.accessibilityLabel("路线时间回看") }
                if !route.points.isEmpty { Text(route.points[index].at.formatted(date: .abbreviated, time: .standard)).font(.subheadline.monospacedDigit()) }
                Text("\(route.points.count) 个实际采样点 · \(Set(route.points.map(\.segment)).count) 段").font(.subheadline)
                TextField("路线标题", text: $title).font(.title2.bold())
                TextField("沿途故事", text: $note, axis: .vertical).lineLimit(3...8)
                Picker("交通方式（手动）", selection: $transport) { ForEach(["未知","步行","跑步","骑行","驾车","公共交通","其他"], id: \.self) { Text($0) } }
                Picker("关联行程", selection: $tripID) { Text("独立路线").tag(UUID?.none); ForEach(store.data.trips) { Text($0.title).tag(Optional($0.id)) } }
                Text(route.start.formatted(date: .complete, time: .shortened)).foregroundStyle(.secondary)
                ForEach(Array((route.gaps ?? []).enumerated()), id: \.offset) { _, gap in Label(gap.reason + " · " + gap.from.formatted(date: .abbreviated, time: .shortened), systemImage: "line.diagonal").font(.caption).foregroundStyle(.secondary) }
                Text("滑动只回看实际采样，不插值推算你经过的位置。中断片段保持分开；路线不自动证明活动或成果。") .font(.caption).foregroundStyle(.secondary)
                Button("保存说明") { _ = store.saveRoute(route, title: title, note: note, transport: transport, tripID: tripID) }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("删除这段路线", role: .destructive) { delete = true }.disabled(route.end == nil)
            }.padding() }.navigationTitle("沿途").navigationBarTitleDisplayMode(.inline)
                .onAppear { if !initialized { initialized = true; title = route.title; note = route.note ?? ""; transport = route.transport ?? "未知"; tripID = route.tripID; position = Double(max(0, route.points.count - 1)) } }
                .confirmationDialog("删除整段精确路线？", isPresented: $delete, titleVisibility: .visible) { Button("删除", role: .destructive) { store.deleteRoute(route) }; Button("取消", role: .cancel) {} } message: { Text("行程和其他文字记忆会保留，路线采样与其说明将删除。") }
        } else { ContentUnavailableView("路线已删除", systemImage: "map") }
        }
    }
}
