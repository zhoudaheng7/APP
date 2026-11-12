import Foundation
import CoreLocation
import CryptoKit

struct VisitObservation {
    var source = "apple.visits"
    var latitude: Double
    var longitude: Double
    var accuracy: Double
    var arrival: Date?
    var departure: Date?
    var receivedAt = Date()
    var key: String {
        if let arrival { return source + ":arrival:" + String(Int64((arrival.timeIntervalSince1970 * 1000).rounded())) }
        return source + ":departure:" + String(Int64(((departure?.timeIntervalSince1970 ?? 0) * 1000).rounded())) + String(format: ":%.4f:%.4f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude)
    }
    var id: UUID {
        var bytes = Array(SHA256.hash(data: Data(("dayisle.visit:" + key).utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80; bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
    }
}

extension LifeStore {
    var visitsEnabled: Bool { data.collectionWindows.contains { $0.mode == "visits" && $0.end == nil } }
    func setVisitCollection(_ enabled: Bool, at date: Date = Date()) -> Bool {
        guard enabled != visitsEnabled else { return true }
        return commit(kind: "collection.visits", id: UUID()) { state in
            if enabled { state.collectionWindows.append(CollectionWindow(start: date, mode: "visits")) }
            else { for i in state.collectionWindows.indices where state.collectionWindows[i].mode == "visits" && state.collectionWindows[i].end == nil { state.collectionWindows[i].end = date } }
        }
    }
    @discardableResult func receiveVisit(_ observation: VisitObservation) -> Bool {
        guard observation.accuracy.isFinite, observation.accuracy >= 0,
              observation.arrival != nil || observation.departure != nil,
              !data.tombstones.contains(where: { $0.kind == "visit" && $0.id == observation.id }) else { return false }
        let existing = data.visits.first { $0.observationKey == observation.key }
        let occurred = observation.arrival ?? observation.departure!
        let approved = data.collectionWindows.contains { $0.mode == "visits" && occurred >= $0.start && occurred <= ($0.end ?? observation.receivedAt) }
        guard approved else { return false }
        // After pause/revoke, only an already known authorized observation can be enriched,
        // and only with a departure that itself occurred inside the approved window.
        if !visitsEnabled && existing == nil { return false }
        if let end = observation.departure, !data.collectionWindows.contains(where: { $0.mode == "visits" && end >= $0.start && end <= ($0.end ?? observation.receivedAt) }) { return false }
        if let existing, existing.state != "inferred" { return true }
        if let existing, existing.arrival == observation.arrival && existing.departure == observation.departure { return true }
        return commit(kind: "visit.observe", id: observation.id) { state in
            if let i = state.visits.firstIndex(where: { $0.observationKey == observation.key }) {
                state.visits[i].departure = observation.departure ?? state.visits[i].departure; state.visits[i].revision += 1
            } else {
                let visit = LifeVisit(id: observation.id, observationKey: observation.key, source: observation.source, latitude: observation.latitude, longitude: observation.longitude, accuracy: observation.accuracy, arrival: observation.arrival, departure: observation.departure, receivedAt: observation.receivedAt)
                state.visits.insert(visit, at: 0)
            }
        }
    }
    func reviseVisit(_ original: LifeVisit, placeID: UUID?, arrival: Date?, departure: Date?, note: String, state factState: String, timeZone: String? = nil) -> Bool {
        commit(kind: "visit.review", id: original.id) { state in
            guard let i = state.visits.firstIndex(where: { $0.id == original.id }), state.visits[i].revision == original.revision else { throw LifeError.invalidReference }
            try state.audit(state.visits[i], id: original.id, kind: "visit", revision: original.revision)
            state.visits[i].placeID = placeID; state.visits[i].arrival = arrival; state.visits[i].departure = departure
            state.visits[i].note = note; state.visits[i].state = factState; state.visits[i].revision += 1
            state.visits[i].timeZoneSource = timeZone == nil ? nil : "user"; if let timeZone { state.visits[i].timeZone = timeZone }
        }
    }
    func deleteVisit(_ visit: LifeVisit) {
        _ = commit(kind: "visit.delete", id: visit.id) { state in state.tombstone(visit.id, kind: "visit"); state.applyDeletionHistory() }
    }
    func beginRoute(background: Bool) -> Bool {
        if let route = runningRoute {
            return commit(kind: "route.resume", id: route.id) { state in
                if let i = state.routes.firstIndex(where: { $0.id == route.id }) { state.routes[i].backgroundEnabled = background }
            }
        }
        var route = LifeRoute(title: "散步与沿途"); route.backgroundEnabled = background; route.gaps = []
        return commit(kind: "route.start", id: route.id) { $0.routes.insert(route, at: 0) }
    }
    func routeGap(_ reason: String, at date: Date = Date()) {
        guard let route = runningRoute, route.gaps?.last?.to != nil || (route.gaps ?? []).isEmpty else { return }
        _ = commit(kind: "route.gap", id: route.id) { state in
            if let i = state.routes.firstIndex(where: { $0.id == route.id }) { state.routes[i].gaps = (state.routes[i].gaps ?? []) + [RouteGap(from: date, reason: reason)] }
        }
    }
    func saveRoute(_ original: LifeRoute, title: String, note: String, transport: String, tripID: UUID?, purpose: String? = nil) -> Bool {
        commit(kind: "route.edit", id: original.id) { state in
            guard let i = state.routes.firstIndex(where: { $0.id == original.id }), state.routes[i] == original else { throw LifeError.message("路线已更新，请停止采集并核对后重试。") }
            state.routes[i].title = title; state.routes[i].note = note; state.routes[i].transport = transport; state.routes[i].tripID = tripID
            state.routes[i].purpose = purpose
        }
    }
    func deleteRoute(_ route: LifeRoute) {
        guard route.end != nil else { error = "请先结束路线记录。"; return }
        _ = commit(kind: "route.delete", id: route.id) { state in state.tombstone(route.id, kind: "route"); state.applyDeletionHistory() }
    }
    func deleteKnownPlace(_ place: KnownPlace) {
        _ = commit(kind: "known-place.delete", id: place.id) { state in state.tombstone(place.id, kind: "known-place"); state.applyDeletionHistory() }
    }
    func deleteTrip(_ trip: LifeTrip) {
        _ = commit(kind: "trip.delete", id: trip.id) { state in state.tombstone(trip.id, kind: "trip"); state.applyDeletionHistory() }
    }
}
