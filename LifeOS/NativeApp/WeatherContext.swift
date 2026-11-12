import SwiftUI

struct WeatherDay: Decodable {
    struct Values: Decodable {
        var time: [String]
        var weather_code: [Int?]
        var temperature_2m_max: [Double?]
        var temperature_2m_min: [Double?]
        var precipitation_sum: [Double?]
    }
    struct Units: Decodable { var temperature_2m_max: String; var temperature_2m_min: String; var precipitation_sum: String }
    var daily: Values
    var daily_units: Units
    func text(expectedDay: String) throws -> String {
        guard daily.time == [expectedDay], daily.weather_code.count == 1, daily.temperature_2m_max.count == 1, daily.temperature_2m_min.count == 1, daily.precipitation_sum.count == 1,
              daily_units.temperature_2m_max == "°C",daily_units.temperature_2m_min == "°C",daily_units.precipitation_sum == "mm" else { throw LifeError.message("天气响应的日期或单位不匹配。") }
        func number(_ value: Double?) throws -> String { guard let value else { return "未知" }; guard value.isFinite else { throw LifeError.invalidValue }; return value.formatted(.number.precision(.fractionLength(1))) }
        return "最高温：" + (try number(daily.temperature_2m_max[0])) + " °C\n最低温：" + (try number(daily.temperature_2m_min[0])) + " °C\n降水：" + (try number(daily.precipitation_sum[0])) + " mm\n天气：" + Self.code(daily.weather_code[0])
    }
    static func code(_ value: Int?) -> String {
        guard let value else { return "未知" }
        switch value {
        case 0: return "晴"; case 1...3: return "少云至阴"; case 45,48: return "雾"; case 51...57: return "毛毛雨或冻毛毛雨"; case 61...67: return "雨或冻雨"; case 71...77: return "雪"; case 80...82: return "阵雨"; case 85,86: return "阵雪"; case 95...99: return "雷暴"; default: return "未知代码 \(value)"
        }
    }
}

enum WeatherRequest {
    static func coordinate(_ value: Double) -> Double { (value * 10).rounded() / 10 }
    static func url(latitude: Double,longitude: Double,day: String,zone: String,historical: Bool) throws -> URL {
        guard (-90...90).contains(latitude),(-180...180).contains(longitude),TimeZone(identifier:zone) != nil else { throw LifeError.invalidValue }
        var c = URLComponents(string: historical ? "https://archive-api.open-meteo.com/v1/archive" : "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [URLQueryItem(name:"latitude",value:String(coordinate(latitude))),URLQueryItem(name:"longitude",value:String(coordinate(longitude))),URLQueryItem(name:"start_date",value:day),URLQueryItem(name:"end_date",value:day),URLQueryItem(name:"timezone",value:zone),URLQueryItem(name:"daily",value:"weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum")]
        if historical { c.queryItems?.append(URLQueryItem(name:"models",value:"era5")) }
        guard let result = c.url else { throw LifeError.invalidValue }; return result
    }
}

struct WeatherContextView: View {
    @Environment(LifeStore.self) private var store
    @State private var placeID: UUID?
    @State private var day = Date()
    @State private var zone: String? = TimeZone.current.identifier
    @State private var busy = false
    @State private var result = ""
    @State private var error = ""
    var place: KnownPlace? { store.data.knownPlaces.first { $0.id == placeID } }
    var range: ClosedRange<Date> { Date(timeIntervalSince1970:-946771200)...Calendar.current.date(byAdding:.day,value:14,to:Date())! }
    var body: some View {
        Form {
            Section("选择地点与日期") {
                Picker("稳定地点",selection:$placeID) { Text("先选择已保存地点").tag(UUID?.none); ForEach(store.data.knownPlaces) { Text($0.title).tag(Optional($0.id)) } }.disabled(busy)
                DatePicker("日期",selection:$day,in:range,displayedComponents:.date).disabled(busy)
                AttributionZonePicker(zone:$zone).disabled(busy)
                if let place { Text(String(format:"将发送约 %.1f°, %.1f° 的粗略坐标与所选日期、时区。",WeatherRequest.coordinate(place.latitude),WeatherRequest.coordinate(place.longitude))).font(.caption) }
                Button("同意发送并查询天气",systemImage:"cloud.sun") { Task { await load() } }.disabled(place == nil || zone == nil || busy)
                if busy { ProgressView() }; if !error.isEmpty { Text(error).foregroundStyle(.secondary) }
            }
            if !result.isEmpty { Section("天气上下文") { Text(result).textSelection(.enabled); ShareLink("分享这份文字",item:result); Button("清除结果") { result = "" } } }
            Section("来源与隐私") {
                Text("Open-Meteo 天气模型 / 历史ERA5再分析，CC BY 4.0。本版仅用于无广告、无订阅的私人非商业用途。模型网格天气不等于你所在位置的实测或灾害预警。旧日期可能尚无数据，空值保持未知。")
                Text("不会读取当前定位。点击查询才向提供方发送四舍五入到0.1°的坐标；提供方可能保留含坐标和IP的日志。结果不自动保存、生成活动或进入Obsidian。")
                Link("数据与许可说明",destination:URL(string:"https://open-meteo.com/en/docs/historical-weather-api")!)
                Link("提供方隐私政策",destination:URL(string:"https://open-meteo.com/en/terms")!)
            }.font(.caption).foregroundStyle(.secondary)
        }.navigationTitle("天气上下文").onChange(of:placeID) { _,_ in result = "" }.onChange(of:day) { _,_ in result = "" }.onChange(of:zone) { _,_ in result = "" }
    }
    @MainActor func load() async {
        guard let place,let zone,!busy else { return }; busy = true; result = ""; error = ""; defer { busy = false }
        do {
            let key = LifeSnapshot.dayKey(day,zone:TimeZone.current)
            let historical = Calendar.current.startOfDay(for:day) < Calendar.current.date(byAdding:.day,value:-7,to:Calendar.current.startOfDay(for:Date()))!
            let url = try WeatherRequest.url(latitude:place.latitude,longitude:place.longitude,day:key,zone:zone,historical:historical)
            let configuration = URLSessionConfiguration.ephemeral; configuration.httpShouldSetCookies = false; configuration.urlCache = nil
            let session = URLSession(configuration:configuration); defer { session.invalidateAndCancel() }
            var request = URLRequest(url:url); request.timeoutInterval = 20
            let (stream,response) = try await session.bytes(for:request)
            guard let http = response as? HTTPURLResponse,http.statusCode == 200,http.url?.scheme == "https",http.url?.host == url.host else { throw LifeError.message("天气服务暂不可用。") }
            var data = Data()
            for try await byte in stream { guard data.count < 256 * 1024 else { throw LifeError.message("天气响应超过限制。") }; data.append(byte) }
            let content = try JSONDecoder().decode(WeatherDay.self,from:data).text(expectedDay:key)
            result = place.title + " · " + key + " · " + zone + "\n" + content + "\n来源：Open-Meteo · " + (historical ? "ERA5历史再分析" : "天气模型（近期历史/预报）") + "\n读取于：" + Date().formatted() + "\nhttps://open-meteo.com/ · CC BY 4.0\n约0.1°坐标查询，非个人位置实测。"
        } catch { self.error = "本次天气未知。" + error.localizedDescription }
    }
}
