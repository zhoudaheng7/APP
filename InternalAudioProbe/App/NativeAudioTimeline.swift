import AudioCore
import QuartzCore
import SwiftUI
import UIKit

struct NativeAudioTimeline: UIViewRepresentable {
    let file: URL
    let waveform: AudioWaveform
    // Observe transport changes here: the controller reference itself stays identical when
    // play/pause changes, so a plain let can leave updateUIView and the display link dormant.
    @ObservedObject var playback: PlaybackController
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
    private let hintLabel = UILabel()
    private let slider = AudioScrubSlider()
    private let baseWave = CAShapeLayer()
    private let scrubBackground = CAShapeLayer()
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
#if DEBUG
    private let probe = ProcessInfo.processInfo.arguments.contains("--ui-performance-probe")
#else
    private let probe = false
#endif
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
        hintLabel.text = "左右拖动音轨"
        hintLabel.font = .systemFont(ofSize: 9)
        hintLabel.textColor = UIColor(red: 0.27, green: 0.64, blue: 0.60, alpha: 1)
        hintLabel.textAlignment = .center
        hintLabel.accessibilityIdentifier = "waveform-drag-hint"
        addSubview(hintLabel)
        layer.addSublayer(scrubBackground)
        scrubBackground.fillColor = UIColor(red: 0.04, green: 0.17, blue: 0.18, alpha: 0.28).cgColor
        layer.addSublayer(baseWave)
        layer.addSublayer(playedWave)
        baseWave.fillColor = UIColor(red: 0.18, green: 0.28, blue: 0.34, alpha: 1).cgColor
        playedWave.fillColor = UIColor(red: 0.20, green: 0.88, blue: 0.77, alpha: 1).cgColor
        playedMask.backgroundColor = UIColor.white.cgColor
        playedWave.mask = playedMask
        slider.minimumValue = 0
        // The waveform is the track; UIKit's plain UIControl owns the entire touch region.
        let thumb = UIGraphicsImageRenderer(size: CGSize(width: 18, height: 30)).image { context in
            UIColor(red: 0.85, green: 0.98, blue: 0.96, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 7.5, y: 0, width: 3, height: 30), cornerRadius: 1.5).fill()
            context.cgContext.fillEllipse(in: CGRect(x: 4.5, y: 10.5, width: 9, height: 9))
        }
        slider.setThumbImage(thumb, for: .normal)
        slider.setThumbImage(thumb, for: .highlighted)
        slider.accessibilityLabel = "音轨波形，左右拖动定位"
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
        let stem = file.deletingPathExtension().lastPathComponent
        let shortName = stem == "recording" ? "主轨" : stem.replacingOccurrences(of: "part-", with: "#")
        let text = showFilename ? "\(shortName) · \(size)" : size
        if sizeLabel.text != text { sizeLabel.text = text }
        render(at: active ? playback.currentTime : 0, updateSlider: true)
        updateLink()
        if !playback.isPlaying { saveProbe() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        clockLabel.frame = CGRect(x: 0, y: 0, width: bounds.width * 0.42, height: 14)
        hintLabel.frame = CGRect(x: bounds.width * 0.42, y: 0, width: bounds.width * 0.33, height: 14)
        sizeLabel.frame = CGRect(x: bounds.width * 0.75, y: 0, width: bounds.width * 0.25, height: 14)
        slider.frame = CGRect(x: 0, y: 13, width: bounds.width, height: 40)
        guard geometrySize != bounds.size else { return }
        geometrySize = bounds.size
        geometryBuilds += 1
        let path = UIBezierPath()
        let maximum = max(peaks.max() ?? 0, 0.0001)
        let waveWidth = max(1, bounds.width - 18)
        let step = waveWidth / CGFloat(max(1, peaks.count))
        for (index, peak) in peaks.enumerated() {
            let height = max(1.5, CGFloat(sqrt(max(0, peak) / maximum)) * 28)
            let rect = CGRect(x: 9 + CGFloat(index) * step, y: 19 + (28 - height) / 2,
                              width: max(1, step - 1.5), height: height)
            path.append(UIBezierPath(roundedRect: rect, cornerRadius: 1))
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        baseWave.frame = bounds; playedWave.frame = bounds
        scrubBackground.frame = bounds
        scrubBackground.path = UIBezierPath(roundedRect: CGRect(x: 0, y: 16, width: bounds.width, height: 34), cornerRadius: 7).cgPath
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
        playedMask.frame = CGRect(x: 0, y: 0, width: 9 + max(0, bounds.width - 18) * progress, height: bounds.height)
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
        render(at: Double(slider.value), updateSlider: false)
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
#if DEBUG
        guard probe else { return }
        let metrics: [String: Any] = ["requestedHz": requestedHz, "frameSamples": frameCount,
            "observedCallbackHz": frameSeconds > 0 ? Double(frameCount) / frameSeconds : 0,
            "waveformGeometryBuilds": geometryBuilds, "seekCommits": playback?.seekCommitCount ?? 0,
            "updatesSwiftUIOnEveryFrame": false, "nativeDeviceFPSVerified": false,
            "gestureEvents": gestureEvents]
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent("UIProbe.json"), options: .atomic)
#endif
    }
    private func recordProbeEvent(_ event: String) {
#if DEBUG
        guard probe else { return }
        if gestureEvents.count >= 32 { gestureEvents.removeFirst() }
        gestureEvents.append("\(event): touch=\(slider.trackingGesture), tracking=\(slider.isTracking), dragging=\(dragging), seeks=\(playback?.seekCommitCount ?? 0)")
#endif
    }
    private static func clock(_ value: Double) -> String {
        let seconds = max(0, Int(value.isFinite ? value : 0))
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private final class AudioScrubSlider: UIControl {
    var minimumValue: Float = 0 { didSet { setValue(value, animated: false) } }
    var maximumValue: Float = 1 { didSet { setValue(value, animated: false) } }
    private(set) var value: Float = 0
    private let cursor = UIImageView()
    var onBegin: (() -> Void)?
    var onEnd: (() -> Void)?
    var onCancel: (() -> Void)?
    private(set) var trackingGesture = false
    private var generation = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(cursor)
        cursor.isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityTraits = [.adjustable]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setThumbImage(_ image: UIImage?, for state: UIControl.State) {
        cursor.image = image
        setNeedsLayout()
    }
    func setValue(_ newValue: Float, animated: Bool) {
        value = min(max(minimumValue, newValue), maximumValue)
        positionCursor()
    }
    override func layoutSubviews() { super.layoutSubviews(); positionCursor() }
    private func positionCursor() {
        let fraction = maximumValue > minimumValue ? CGFloat((value - minimumValue) / (maximumValue - minimumValue)) : 0
        CATransaction.begin(); CATransaction.setDisableActions(true)
        cursor.frame = CGRect(x: max(0, bounds.width - 18) * fraction, y: (bounds.height - 30) / 2, width: 18, height: 30)
        CATransaction.commit()
    }
    override func accessibilityIncrement() { adjust(by: 5) }
    override func accessibilityDecrement() { adjust(by: -5) }
    private func adjust(by seconds: Float) {
        guard isEnabled else { return }
        setValue(value + seconds, animated: false)
        sendActions(for: .valueChanged)
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        generation += 1
        trackingGesture = true
        updateValue(at: touch.location(in: self))
        onBegin?()
        sendActions(for: .valueChanged)
        return true
    }
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        updateValue(at: touch.location(in: self))
        sendActions(for: .valueChanged)
        return true
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        if let touch { updateValue(at: touch.location(in: self)); sendActions(for: .valueChanged) }
        onEnd?()
        finishEventBatch()
    }
    override func cancelTracking(with event: UIEvent?) {
        onCancel?()
        finishEventBatch()
    }
    private func updateValue(at point: CGPoint) {
        // Any point on the waveform can start a drag; it need not begin on the tiny playhead.
        let start: CGFloat = 9
        let end = bounds.width - 9
        let fraction = min(1, max(0, (point.x - start) / max(1, end - start)))
        setValue(minimumValue + Float(fraction) * (maximumValue - minimumValue), animated: false)
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
