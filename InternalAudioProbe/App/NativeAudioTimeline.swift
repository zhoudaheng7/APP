import AudioCore
import QuartzCore
import SwiftUI
import UIKit

struct NativeAudioTimeline: UIViewRepresentable {
    let file: URL
    let waveform: AudioWaveform
    let playback: PlaybackController
    let enabled: Bool
    let showFilename: Bool

    func makeUIView(context: Context) -> AudioTimelineView { AudioTimelineView() }
    func updateUIView(_ view: AudioTimelineView, context: Context) {
        view.configure(file: file, waveform: waveform, playback: playback,
                       enabled: enabled, showFilename: showFilename)
    }
    static func dismantleUIView(_ view: AudioTimelineView, coordinator: ()) { view.detach() }
}

/// UIKit owns the moving thumb/clock/mask. No display-link tick invalidates SwiftUI or the List.
final class AudioTimelineView: UIView {
    private let clockLabel = UILabel()
    private let sizeLabel = UILabel()
    private let slider = AudioScrubSlider()
    private let baseWave = CAShapeLayer()
    private let playedWave = CAShapeLayer()
    private let playedMask = CALayer()
    private var displayLink: CADisplayLink?
    private let frameTarget = TimelineFrameTarget()
    private weak var playback: PlaybackController?
    private var file: URL?
    private var duration: Double = 0
    private var peaks: [Float] = []
    private var geometrySize = CGSize.zero
    private var dragging = false
    private var lastSecond = -1
    private var lastPercent = -1
    private var active: Bool { playback?.currentURL == file && file != nil }
    private let probe = ProcessInfo.processInfo.arguments.contains("--ui-performance-probe")
    private var frameCount = 0
    private var frameSeconds: Double = 0
    private var lastTimestamp: Double = 0
    private var geometryBuilds = 0
    private var requestedHz = 60
    private var gestureEvents: [String] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        frameTarget.owner = self
        clockLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        clockLabel.textColor = UIColor(white: 0.87, alpha: 1)
        clockLabel.accessibilityIdentifier = "playback-time"
        sizeLabel.font = .systemFont(ofSize: 10)
        sizeLabel.textColor = UIColor(white: 0.58, alpha: 1)
        sizeLabel.textAlignment = .right
        sizeLabel.lineBreakMode = .byTruncatingMiddle
        sizeLabel.accessibilityIdentifier = "audio-file-size"
        addSubview(clockLabel)
        addSubview(sizeLabel)
        layer.addSublayer(baseWave)
        layer.addSublayer(playedWave)
        baseWave.fillColor = UIColor(red: 0.18, green: 0.28, blue: 0.34, alpha: 1).cgColor
        playedWave.fillColor = UIColor(red: 0.20, green: 0.88, blue: 0.77, alpha: 1).cgColor
        playedMask.backgroundColor = UIColor.white.cgColor
        playedWave.mask = playedMask
        slider.minimumValue = 0
        slider.minimumTrackTintColor = UIColor(red: 0.20, green: 0.88, blue: 0.77, alpha: 1)
        slider.maximumTrackTintColor = UIColor(red: 0.15, green: 0.23, blue: 0.29, alpha: 1)
        let thumb = UIGraphicsImageRenderer(size: CGSize(width: 18, height: 18)).image { context in
            UIColor(red: 0.85, green: 0.98, blue: 0.96, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 18, height: 18))
        }
        slider.setThumbImage(thumb, for: .normal)
        slider.setThumbImage(thumb, for: .highlighted)
        slider.accessibilityLabel = "播放进度，可拖动定位"
        slider.accessibilityIdentifier = "audio-progress"
        slider.accessibilityHint = "拖动预览位置，松手后定位音频"
        slider.onBegin = { [weak self] in self?.beginDrag() }
        slider.onEnd = { [weak self] in self?.endDrag() }
        slider.onCancel = { [weak self] in self?.cancelDrag() }
        slider.addTarget(self, action: #selector(changeValue), for: .valueChanged)
        addSubview(slider)
        NotificationCenter.default.addObserver(self, selector: #selector(updateLink),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateLink),
            name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { displayLink?.invalidate(); NotificationCenter.default.removeObserver(self) }

    func configure(file: URL, waveform: AudioWaveform, playback: PlaybackController,
                   enabled: Bool, showFilename: Bool) {
        self.file = file
        self.playback = playback
        duration = playback.currentURL == file ? playback.duration : waveform.duration
        slider.maximumValue = Float(max(0.01, duration))
        slider.isEnabled = enabled && duration > 0
        if peaks != waveform.peaks { peaks = waveform.peaks; geometrySize = .zero; setNeedsLayout() }
        let bytes = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        let text = showFilename ? "\(file.lastPathComponent) · \(size)" : size
        if sizeLabel.text != text { sizeLabel.text = text }
        render(at: active ? playback.currentTime : 0, updateSlider: true)
        updateLink()
        if !playback.isPlaying { saveProbe() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        clockLabel.frame = CGRect(x: 0, y: 0, width: bounds.width * 0.55, height: 14)
        sizeLabel.frame = CGRect(x: bounds.width * 0.55, y: 0, width: bounds.width * 0.45, height: 14)
        slider.frame = CGRect(x: 0, y: 38, width: bounds.width, height: 28)
        guard geometrySize != bounds.size else { return }
        geometrySize = bounds.size
        geometryBuilds += 1
        let path = UIBezierPath()
        let maximum = max(peaks.max() ?? 0, 0.0001)
        let step = bounds.width / CGFloat(max(1, peaks.count))
        for (index, peak) in peaks.enumerated() {
            let height = max(1.5, CGFloat(sqrt(max(0, peak) / maximum)) * 20)
            let rect = CGRect(x: CGFloat(index) * step, y: 17 + (20 - height) / 2,
                              width: max(1, step - 1.5), height: height)
            path.append(UIBezierPath(roundedRect: rect, cornerRadius: 1))
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        baseWave.frame = bounds; playedWave.frame = bounds
        baseWave.path = path.cgPath; playedWave.path = path.cgPath
        CATransaction.commit()
        render(at: dragging ? Double(slider.value) : active ? playback?.currentTime ?? 0 : 0, updateSlider: !dragging)
    }

    override func didMoveToWindow() { super.didMoveToWindow(); updateLink() }
    func detach() { if dragging { cancelDrag() }; displayLink?.invalidate(); displayLink = nil }

    @objc private func updateLink() {
        let needed = window != nil && UIApplication.shared.applicationState == .active &&
            (dragging || (active && playback?.isPlaying == true))
        if needed && displayLink == nil {
            let link = CADisplayLink(target: frameTarget, selector: #selector(TimelineFrameTarget.tick(_:)))
            requestedHz = window?.windowScene?.screen.maximumFramesPerSecond ?? 60
            let maximum = Float(max(1, requestedHz))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, maximum), maximum: maximum, preferred: maximum)
            link.add(to: .main, forMode: .common)
            lastTimestamp = 0
            displayLink = link
        } else if !needed {
            displayLink?.invalidate(); displayLink = nil; lastTimestamp = 0
        }
    }

    fileprivate func frame(_ link: CADisplayLink) {
        if probe {
            if lastTimestamp > 0 { frameSeconds += link.timestamp - lastTimestamp; frameCount += 1 }
            lastTimestamp = link.timestamp
        }
        if !dragging {
            playback?.synchronizePlaybackState()
            render(at: playback?.currentTime ?? 0, updateSlider: true)
        }
    }

    private func render(at seconds: Double, updateSlider: Bool) {
        // The player's clock must never pull the thumb back while the finger is tracking.
        guard !dragging || !updateSlider else { return }
        let time = min(max(0, seconds), duration)
        if updateSlider && !slider.isTracking { slider.setValue(Float(time), animated: false) }
        let progress = duration > 0 ? time / duration : 0
        CATransaction.begin(); CATransaction.setDisableActions(true)
        playedMask.frame = CGRect(x: 0, y: 0, width: bounds.width * progress, height: bounds.height)
        CATransaction.commit()
        let second = Int(time)
        if lastSecond != second || clockLabel.text == nil {
            lastSecond = second
            clockLabel.text = "\(Self.clock(time)) / \(Self.clock(duration))"
        }
        let percent = Int(progress * 100)
        if percent != lastPercent || probe {
            lastPercent = percent
            slider.accessibilityValue = probe ? "\(percent)% · 定位提交 \(playback?.seekCommitCount ?? 0)" : "\(percent)%"
        }
    }

    @objc private func beginDrag() {
        guard !dragging, let file else { return }
        recordProbeEvent("begin")
        dragging = true
        playback?.beginScrubbing(file)
        updateLink()
    }
    @objc private func changeValue() {
        recordProbeEvent("value")
        render(at: Double(slider.value), updateSlider: false)
        // VoiceOver's discrete adjustments have no touch-up event.
        if !slider.trackingGesture && !dragging, let file {
            playback?.seek(file, to: Double(slider.value))
            saveProbe()
        }
    }
    @objc private func endDrag() {
        guard dragging, let file else { return }
        recordProbeEvent("end")
        let target = Double(slider.value)
        dragging = false
        playback?.seek(file, to: target)
        render(at: target, updateSlider: false)
        updateLink(); saveProbe()
    }
    @objc private func cancelDrag() {
        guard dragging else { return }
        dragging = false
        playback?.cancelScrubbing()
        render(at: active ? playback?.currentTime ?? 0 : 0, updateSlider: true)
        updateLink()
    }
    private func saveProbe() {
        guard probe else { return }
        let metrics: [String: Any] = ["requestedHz": requestedHz, "frameSamples": frameCount,
            "observedCallbackHz": frameSeconds > 0 ? Double(frameCount) / frameSeconds : 0,
            "waveformGeometryBuilds": geometryBuilds, "seekCommits": playback?.seekCommitCount ?? 0,
            "updatesSwiftUIOnEveryFrame": false, "nativeDeviceFPSVerified": false,
            "gestureEvents": gestureEvents]
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent("UIProbe.json"), options: .atomic)
    }
    private func recordProbeEvent(_ event: String) {
        guard probe else { return }
        if gestureEvents.count >= 32 { gestureEvents.removeFirst() }
        gestureEvents.append("\(event): touch=\(slider.trackingGesture), tracking=\(slider.isTracking), dragging=\(dragging), seeks=\(playback?.seekCommitCount ?? 0)")
    }
    private static func clock(_ value: Double) -> String {
        let seconds = max(0, Int(value.isFinite ? value : 0))
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private final class AudioScrubSlider: UISlider {
    var onBegin: (() -> Void)?
    var onEnd: (() -> Void)?
    var onCancel: (() -> Void)?
    private(set) var trackingGesture = false
    private var generation = 0

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        generation += 1
        trackingGesture = true
        let accepted = super.beginTracking(touch, with: event)
        if accepted { onBegin?() } else { trackingGesture = false }
        return accepted
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        super.endTracking(touch, with: event)
        onEnd?()
        finishEventBatch()
    }
    override func cancelTracking(with event: UIEvent?) {
        super.cancelTracking(with: event)
        onCancel?()
        finishEventBatch()
    }
    private func finishEventBatch() {
        // UIKit can deliver a final valueChanged after tracking becomes false. Keep the
        // touch transaction open until that event batch ends, so it isn't treated as VoiceOver.
        let completedGeneration = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == completedGeneration else { return }
            self.trackingGesture = false
        }
    }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -4, dy: -8).contains(point)
    }
}

@MainActor private final class TimelineFrameTarget: NSObject {
    weak var owner: AudioTimelineView?
    @objc func tick(_ link: CADisplayLink) { owner?.frame(link) }
}
