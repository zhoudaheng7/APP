import XCTest
import CoreData
import UIKit
@testable import LifeOS

@MainActor final class V2StoreTests: XCTestCase {
    func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Dayisle-Test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }; return url
    }
    func fixture(_ name: String) throws -> Data { try Data(contentsOf: XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))) }
    func testActualLegacySQLitePayloadMigratesAndReopensWithoutChangingIDs() throws {
        let parent = try temporaryDirectory(), bytes = try fixture("legacy-v1")
        do {
            let legacy = LifeStore(directory: parent)
            let row = NSEntityDescription.insertNewObject(forEntityName: "LifeOSSnapshot", into: legacy.container.viewContext)
            row.setValue("current", forKey: "key"); row.setValue(bytes, forKey: "payload"); try legacy.container.viewContext.save()
        }
        let upgraded = LifeStore(directory: parent); XCTAssertTrue(upgraded.ready, upgraded.error ?? "")
        XCTAssertEqual(upgraded.data.schemaVersion,2); XCTAssertEqual(upgraded.data.tasks[0].revision,3)
        XCTAssertEqual(upgraded.data.tasks[0].note,"迁移前的原文"); XCTAssertEqual(upgraded.data.keyResults[0].id,upgraded.data.goals[0].id)
        XCTAssertEqual(upgraded.data.measurements[0].keyResultID,upgraded.data.goals[0].id); XCTAssertEqual(upgraded.data.routes[0].points.count,2)
        XCTAssertEqual(try Data(contentsOf: parent.appendingPathComponent("before-v2-migration.json")),bytes)
        XCTAssertTrue(upgraded.addTask(title:"示例：升级后新任务",note:"",goalID:nil))
        let reopened = LifeStore(directory:parent); XCTAssertTrue(reopened.ready); XCTAssertEqual(reopened.data.tasks.count,2); XCTAssertEqual(reopened.data.reviews[0].reflection,"示例：旧版日复盘原文")
    }
    func testCurrentOutcomeUsesObservedTimeAndWeightsWithoutSumming() throws {
        let store=LifeStore(inMemory:true),goal=LifeGoal(title:"示例方向",intention:"",target:10,unit:"本",due:Date())
        XCTAssertTrue(store.addGoal(goal));let second=LifeKeyResult(objectiveID:goal.id,title:"示例递减",baseline:100,target:80,unit:"分",weight:3)
        XCTAssertTrue(store.addKeyResult(second));XCTAssertNil(store.data.objectiveProgress(goal.id))
        var latest=LifeMeasurement(goalID:goal.id,value:5,note:"用户累计读数");latest.keyResultID=goal.id;latest.observedAt=Date(timeIntervalSince1970:2000)
        var older=LifeMeasurement(goalID:goal.id,value:9,note:"晚录入的旧读数");older.keyResultID=goal.id;older.observedAt=Date(timeIntervalSince1970:1000)
        XCTAssertTrue(store.addMeasurement(latest));XCTAssertTrue(store.addMeasurement(older));XCTAssertEqual(store.data.currentMeasurement(for:goal.id)?.value,5)
        var down=LifeMeasurement(goalID:goal.id,value:90,note:"");down.keyResultID=second.id;XCTAssertTrue(store.addMeasurement(down))
        XCTAssertEqual(try XCTUnwrap(store.data.objectiveProgress(goal.id)),0.5,accuracy:0.0001)
        store.rejectMeasurement(latest);XCTAssertEqual(store.data.currentMeasurement(for:goal.id)?.value,9)
    }
    func testOverlappingActualsUseUnionAndDoNotCreateResults() {
        let store=LifeStore(inMemory:true),start=Date(timeIntervalSince1970:1000)
        XCTAssertTrue(store.commit(kind:"fixture.synthetic",id:UUID()){ state in
            state.sessions=[LifeSession(title:"示例A",start:start,end:start.addingTimeInterval(3600),confirmed:true),LifeSession(title:"示例B",start:start.addingTimeInterval(1800),end:start.addingTimeInterval(5400),confirmed:true)]
        })
        XCTAssertEqual(store.data.unionActualSeconds(from:start,to:start.addingTimeInterval(7200)),5400)
        XCTAssertTrue(store.data.measurements.isEmpty);XCTAssertTrue(store.data.tasks.isEmpty)
    }
    func testLateVisitIdentityDeduplicatesAndNeverRevivesDeletedObservation() throws {
        let store=LifeStore(inMemory:true),start=Date(timeIntervalSince1970:1000)
        XCTAssertTrue(store.setVisitCollection(true,at:start))
        var observation=VisitObservation(latitude:30,longitude:120,accuracy:100,arrival:start.addingTimeInterval(10),departure:nil,receivedAt:start.addingTimeInterval(20))
        XCTAssertTrue(store.receiveVisit(observation));let id=try XCTUnwrap(store.data.visits.first?.id)
        observation.departure=start.addingTimeInterval(30);observation.receivedAt=start.addingTimeInterval(40)
        XCTAssertTrue(store.receiveVisit(observation));XCTAssertEqual(store.data.visits.count,1);XCTAssertEqual(store.data.visits[0].id,id)
        let candidate=store.data.visits[0];XCTAssertTrue(store.reviseVisit(candidate,placeID:nil,arrival:candidate.arrival,departure:candidate.departure,note:"本人核对",state:"confirmed"))
        observation.departure=start.addingTimeInterval(60);XCTAssertTrue(store.receiveVisit(observation));XCTAssertEqual(store.data.visits[0].departure,start.addingTimeInterval(30))
        store.deleteVisit(store.data.visits[0]);XCTAssertFalse(store.receiveVisit(observation));XCTAssertTrue(store.data.visits.isEmpty)
    }
    func testPausedCollectionRejectsNewLateFactsAndKeepsUnknownTimes() {
        let store=LifeStore(inMemory:true),start=Date(timeIntervalSince1970:1000)
        XCTAssertTrue(store.setVisitCollection(true,at:start))
        let unknown=VisitObservation(latitude:30,longitude:120,accuracy:100,arrival:nil,departure:start.addingTimeInterval(10),receivedAt:start.addingTimeInterval(20))
        XCTAssertTrue(store.receiveVisit(unknown));XCTAssertNil(store.data.visits[0].arrival)
        XCTAssertTrue(store.setVisitCollection(false,at:start.addingTimeInterval(30)))
        let late=VisitObservation(latitude:31,longitude:121,accuracy:100,arrival:start.addingTimeInterval(1),departure:start.addingTimeInterval(20),receivedAt:start.addingTimeInterval(60))
        XCTAssertFalse(store.receiveVisit(late));XCTAssertEqual(store.data.visits.count,1)
    }
    func preparedPhoto() throws -> PreparedPhoto {
        let renderer=UIGraphicsImageRenderer(size:CGSize(width:30,height:20))
        let raw=renderer.jpegData(withCompressionQuality:0.8){ context in UIColor.systemTeal.setFill();context.cgContext.fill(CGRect(x:0,y:0,width:30,height:20)) }
        return try PhotoProcessor.prepare(raw)
    }
    func testPhotoSnapshotAndBlobAreAtomicAndReopenAsOneStore() throws {
        let parent=try temporaryDirectory(),store=LifeStore(directory:parent),image=try preparedPhoto()
        XCTAssertTrue(PhotoProcessor.isSanitizedJPEG(image.data,width:image.width,height:image.height))
        let photo=LifePhoto(caption:"示例照片",capturedAt:Date(),sha256:LifeStore.fingerprint(image.data),width:image.width,height:image.height,bytes:image.data.count)
        let before=store.data.pendingChanges.count
        XCTAssertFalse(store.addPhoto(photo,bytes:Data("wrong".utf8)));XCTAssertTrue(store.data.photos.isEmpty);XCTAssertEqual(store.data.pendingChanges.count,before)
        XCTAssertTrue(store.addPhoto(photo,bytes:image.data));let reopened=LifeStore(directory:parent)
        XCTAssertTrue(reopened.ready,reopened.error ?? "");XCTAssertEqual(reopened.photoData(photo.id),image.data)
        let backupURL=try XCTUnwrap(reopened.exportBackup());defer{try? FileManager.default.removeItem(at:backupURL)}
        let backup=try LifeStore.decodeBackup(Data(contentsOf:backupURL));XCTAssertEqual(backup.media[photo.id.uuidString],image.data)
        reopened.deletePhoto(photo);XCTAssertTrue(reopened.restoreBackup(backup));XCTAssertTrue(reopened.data.photos.isEmpty);XCTAssertNil(reopened.photoData(photo.id))
    }
    func testCorruptBackupRefusesBeforeAnyMutation() throws {
        let store=LifeStore(inMemory:true);XCTAssertTrue(store.addTask(title:"示例原任务",note:"",goalID:nil))
        var damaged=LifeBackup(snapshot:store.data,media:[:]);damaged.format="unknown"
        let encoder=JSONEncoder();encoder.dateEncodingStrategy = .millisecondsSince1970
        XCTAssertThrowsError(try LifeStore.decodeBackup(encoder.encode(damaged)));XCTAssertEqual(store.data.tasks[0].title,"示例原任务")
    }
    func testCompetingStoreNeverOverwritesAConcurrentCommit() throws {
        let parent=try temporaryDirectory(),first=LifeStore(directory:parent)
        XCTAssertTrue(first.addTask(title:"示例A",note:"",goalID:nil));let second=LifeStore(directory:parent)
        XCTAssertTrue(second.addTask(title:"示例B",note:"",goalID:nil));XCTAssertFalse(first.addTask(title:"示例C",note:"",goalID:nil))
        XCTAssertEqual(Set(first.data.tasks.map(\.title)),Set(["示例A","示例B"]))
        XCTAssertTrue(first.addTask(title:"示例C",note:"",goalID:nil));XCTAssertEqual(first.data.tasks.count,3)
    }
    func testCalendarSaveKeepsPrivatePlanAndMapsActualCommitmentIdempotently() throws {
        let store=LifeStore(inMemory:true),now=Date(),plan=LifePlan(title:"示例私人计划",start:now,end:now.addingTimeInterval(3600))
        XCTAssertTrue(store.addPlan(plan));XCTAssertTrue(store.recordCalendarSave(plan:plan,eventIdentifier:"synthetic-event",calendarIdentifier:"synthetic-calendar"))
        XCTAssertEqual(store.data.plans.count,2);XCTAssertFalse(store.data.plans.first{ $0.id==plan.id }!.isCommitment)
        XCTAssertTrue(store.recordCalendarSave(plan:plan,eventIdentifier:"synthetic-event",calendarIdentifier:"synthetic-calendar"));XCTAssertEqual(store.data.plans.count,2);XCTAssertEqual(store.data.calendarLinks.count,1)
    }
    func testVaultFactAndTerminalRegistryAreAtomicAndNeverRepeat() throws {
        let store=LifeStore(inMemory:true),review=LifeReview(day:"2026-11-12",reflection:"示例：确认草稿",mood:nil),id=UUID()
        let record=VaultOperation(id:id,datasetID:store.data.disclosure.datasetID,clientID:UUID(),payloadHash:String(repeating:"a",count:64),status:"accepted",receipt:Data("synthetic receipt".utf8),finalEntityID:review.id)
        XCTAssertTrue(store.recordVaultResult(record,review:review));XCTAssertTrue(store.recordVaultResult(record,review:review));XCTAssertEqual(store.data.reviews.count,1);XCTAssertEqual(store.data.vaultOperations.count,1)
        let conflict=VaultOperation(id:UUID(),datasetID:record.datasetID,clientID:record.clientID,payloadHash:record.payloadHash,status:"accepted",receipt:record.receipt,finalEntityID:UUID())
        XCTAssertFalse(store.recordVaultResult(conflict,review:LifeReview(day:review.day,reflection:"覆盖",mood:nil)));XCTAssertEqual(store.data.vaultOperations.count,1)
    }
}
