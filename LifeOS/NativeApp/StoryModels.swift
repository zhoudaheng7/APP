import Foundation

struct StorySection: Codable, Equatable { var title: String; var text: String }
struct StoryPhoto: Codable, Identifiable, Equatable { var id = UUID(); var jpeg: Data; var caption: String; var width: Int; var height: Int }
struct StoryRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var createdAt = Date()
    var version = 1
    var previousID: UUID?
    var narrative: String
    var sections: [StorySection]
    var photos: [StoryPhoto]
    // Private provenance stays in the app/backup, never in the exported PDF.
    var sourceKeys: [String]
    var datesIncluded: Bool
    var placesIncluded: Bool
    var peopleIncluded: Bool
    var sourceTextIncluded: Bool
    func validate() throws {
        guard !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,title.utf8.count <= 512,narrative.utf8.count <= 60000,
              sections.count <= 100,sections.allSatisfy({ $0.title.utf8.count <= 2048 && $0.text.utf8.count <= 30000 }),photos.count <= 3,
              photos.allSatisfy({ $0.jpeg.count <= 300000 && PhotoProcessor.isSanitizedJPEG($0.jpeg,width:$0.width,height:$0.height) }),sourceKeys.count <= 100,
              version > 0,createdAt.timeIntervalSince1970.isFinite else { throw LifeError.message("故事内容超过限制或照片校验失败。") }
        guard try JSONEncoder().encode(self).count <= 2 * 1024 * 1024 else { throw LifeError.message("一份故事最多2MB，请减少选择内容。") }
    }
}

struct StorySelection: Codable, Equatable {
    var title = "我的普通日子"
    var narrative = ""
    var sources: [String] = []
    var photos: [UUID] = []
    var dates = false
    var places = false
    var people = false
    var sourceText = false
    var previousID: UUID?
}

extension LifeStore {
    func makeStory(_ choice: StorySelection) throws -> StoryRecord {
        var hidden: [String] = []
        if !choice.places { hidden += data.knownPlaces.map(\.title) + data.places.map(\.title) + data.knownPlaces.flatMap { [$0.city,$0.country,String($0.latitude),String($0.longitude)] } + data.places.flatMap { [String($0.latitude),String($0.longitude)] } }
        if !choice.people { hidden += data.places.flatMap { $0.people ?? [] } + data.reviews.flatMap { $0.people ?? [] } }
        func mask(_ value: String) -> String {
            var output = value
            for term in Set(hidden.filter { !$0.isEmpty }).sorted(by:{ $0.count > $1.count }) { output = output.replacingOccurrences(of:term,with:"[已隐藏]") }
            return output
        }
        func body(_ text: String) -> String { choice.sourceText ? mask(text) : "原文未带出。" }
        var sections: [StorySection] = []; var keys: [String] = []
        for key in choice.sources {
            let parts = key.split(separator:":",maxSplits:1).map(String.init)
            guard parts.count == 2,let id = UUID(uuidString:parts[1]) else { throw LifeError.invalidReference }
            let section: StorySection
            switch parts[0] {
            case "review":
                guard let r = data.reviews.first(where:{ $0.id == id }) else { throw LifeError.invalidReference }
                section = StorySection(title:choice.dates ? r.day + " · 日复盘" : "一日复盘",text:body(r.reflection))
            case "memory":
                guard let r = data.places.first(where:{ $0.id == id }) else { throw LifeError.invalidReference }
                section = StorySection(title:(choice.places ? mask(r.title) : "一段生活记忆") + (choice.dates ? " · " + recordTimeText(r.occurredAt,zone:r.timeZone) : ""),text:body(r.note))
            case "trip":
                guard let r = data.trips.first(where:{ $0.id == id }) else { throw LifeError.invalidReference }
                section = StorySection(title:(choice.places ? mask(r.title) : "一段行程") + (choice.dates ? " · " + recordTimeText(r.start,zone:r.timeZone) : ""),text:body(r.note))
            case "route":
                guard let r = data.routes.first(where:{ $0.id == id }) else { throw LifeError.invalidReference }
                section = StorySection(title:(choice.places ? mask(r.title) : "一段路") + (choice.dates ? " · " + recordTimeText(r.start,zone:r.timeZone) : ""),text:body(r.note ?? "没有手写说明。") + "\n手动用途：" + (r.purpose ?? "未知") + "。路线坐标与轨迹未带出。")
            default: throw LifeError.invalidValue
            }
            sections.append(section); keys.append(key)
        }
        guard Set(keys).count == keys.count,choice.sources.count <= 100,choice.photos.count <= 3,Set(choice.photos).count == choice.photos.count else { throw LifeError.invalidValue }
        var photos: [StoryPhoto] = []
        for id in choice.photos {
            guard let photo = data.photos.first(where:{ $0.id == id }),let bytes = photoData(id) else { throw LifeError.invalidReference }
            let prepared = try PhotoProcessor.prepare(bytes,maxDimension:600)
            guard prepared.data.count <= 300000 else { throw LifeError.message("故事照片仍较大，请减少或更换照片。") }
            photos.append(StoryPhoto(jpeg:prepared.data,caption:choice.sourceText ? mask(photo.caption) : "",width:prepared.width,height:prepared.height))
        }
        let previous = data.stories.first { $0.id == choice.previousID }
        let result = StoryRecord(title:mask(choice.title),version:(previous?.version ?? 0) + 1,previousID:previous?.id,narrative:mask(choice.narrative),sections:sections,photos:photos,sourceKeys:keys,datesIncluded:choice.dates,placesIncluded:choice.places,peopleIncluded:choice.people,sourceTextIncluded:choice.sourceText)
        try result.validate(); return result
    }
    func saveStory(_ story: StoryRecord) -> Bool {
        commit(kind:"story.create",id:story.id) { state in try story.validate(); state.stories.insert(story,at:0) }
    }
    func deleteStory(_ story: StoryRecord) {
        _ = commit(kind:"story.delete",id:story.id) { state in state.stories.removeAll { $0.id == story.id }; state.tombstone(story.id,kind:"story") }
    }
}
