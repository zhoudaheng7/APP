import Foundation

public enum ReceiveDecision: Equatable { case reject, ask, open }
public enum ReceivePolicy {
    public static func decide(enabled: Bool, trusted: Bool, automatic: Bool, foreground: Bool, bluetooth: Bool) -> ReceiveDecision {
        guard enabled, foreground || bluetooth else { return .reject }
        if trusted && automatic { return .open }
        return foreground ? .ask : .reject
    }
}
public enum SoundPack: String, CaseIterable, Codable, Identifiable {
    case swish, spit, hero, girl, captain, robot, silent
    public var id: String { rawValue }
    public var title: String {
        switch self { case .swish: return "轻快咻溜"; case .spit: return "搞怪退退"; case .hero: return "热血少年"; case .girl: return "元气少女"; case .captain: return "冷面队长"; case .robot: return "机械伙伴"; case .silent: return "静音" }
    }
    public var detail: String {
        switch self { case .swish: return "咻—— / 轻轻吸溜"; case .spit: return "退！ / 吸凉粉般吸溜"; case .hero: return "出发吧！ / 接住啦！"; case .girl: return "飞过去咯！ / 收到啦！"; case .captain: return "发射。 / 任务完成。"; case .robot: return "传送启动 / 接收完成"; case .silent: return "关闭声音，保留动画" }
    }
    public func resource(sending: Bool) -> String? { self == .silent ? nil : rawValue + (sending ? "-send" : "-receive") }
}
