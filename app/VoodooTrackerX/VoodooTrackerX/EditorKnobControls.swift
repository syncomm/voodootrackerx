// Shared tactile knob and center-detent pan slider primitives for future editor windows.
// These controls are additive and are not wired into the main tracker window.
import AppKit

/// Tactile editor knob with a dark chamfered body, toothed value halo, and vertical-drag editing.
final class VTXEditorKnobControl: NSControl {
    var minimumValue: Double {
        didSet {
            if minimumValue > maximumValue {
                maximumValue = minimumValue
            }
            setValue(storedValue)
        }
    }

    var maximumValue: Double {
        didSet {
            if maximumValue < minimumValue {
                minimumValue = maximumValue
            }
            setValue(storedValue)
        }
    }

    var value: Double {
        get { storedValue }
        set { setValue(newValue) }
    }

    var normalizedValue: Double {
        get {
            let range = maximumValue - minimumValue
            guard range > 0 else { return 0 }
            return (storedValue - minimumValue) / range
        }
        set {
            let clamped = min(max(newValue, 0), 1)
            setValue(minimumValue + ((maximumValue - minimumValue) * clamped))
        }
    }

    var isEmphasized: Bool {
        didSet { needsDisplay = true }
    }

    override var isEnabled: Bool {
        didSet { needsDisplay = true }
    }

    override var doubleValue: Double {
        get { value }
        set { value = newValue }
    }

    private var storedValue: Double
    private var dragStartY: CGFloat?
    private var dragStartValue: Double?

    init(
        value: Double = 0,
        minimumValue: Double = 0,
        maximumValue: Double = 1,
        isEmphasized: Bool = false
    ) {
        self.minimumValue = minimumValue
        self.maximumValue = max(minimumValue, maximumValue)
        self.storedValue = min(max(value, minimumValue), self.maximumValue)
        self.isEmphasized = isEmphasized
        super.init(frame: NSRect(origin: .zero, size: VTXEditorControlMetrics.knobControlSize))
        configureControl()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        VTXEditorControlMetrics.knobControlSize
    }

    /// Sets the knob value, clamps it to the configured range, and optionally sends the control action.
    @discardableResult
    func setValue(_ newValue: Double, sendAction: Bool = false) -> Bool {
        let clampedValue = clamped(newValue)
        guard abs(clampedValue - storedValue) > Double.ulpOfOne else {
            return false
        }

        storedValue = clampedValue
        needsDisplay = true
        if sendAction {
            self.sendAction(action, to: target)
        }
        return true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        isEnabled
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        guard event.clickCount < 2 else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        dragStartY = point.y
        dragStartValue = storedValue
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled,
              let dragStartY,
              let dragStartValue else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let range = maximumValue - minimumValue
        guard range > 0 else { return }

        let deltaY = Double(point.y - dragStartY)
        let valueDelta = (deltaY / 120.0) * range
        setValue(dragStartValue + valueDelta, sendAction: true)
    }

    override func mouseUp(with event: NSEvent) {
        dragStartY = nil
        dragStartValue = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        context.saveGState()
        context.setAlpha(isEnabled ? 1 : 0.38)
        drawToothedHalo(in: context)
        drawBody(in: context)
        drawIndicator(in: context)
        context.restoreGState()
    }

    private func configureControl() {
        translatesAutoresizingMaskIntoConstraints = false
        cell = NSActionCell()
        isContinuous = true
        wantsLayer = true
        widthAnchor.constraint(equalToConstant: VTXEditorControlMetrics.knobControlSize.width).isActive = true
        heightAnchor.constraint(equalToConstant: VTXEditorControlMetrics.knobControlSize.height).isActive = true
    }

    private func clamped(_ candidate: Double) -> Double {
        let finiteValue = candidate.isFinite ? candidate : minimumValue
        return min(max(finiteValue, minimumValue), maximumValue)
    }

    private var valueAngle: CGFloat {
        Self.startAngle + (CGFloat(normalizedValue) * Self.sweepAngle)
    }

    private func drawToothedHalo(in context: CGContext) {
        let minSide = max(CGFloat(1), min(bounds.width, bounds.height))
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let toothCount = 31
        let innerRadius = minSide * (isEmphasized ? 0.355 : 0.382)
        let outerRadius = minSide * (isEmphasized ? 0.495 : 0.465)
        let litLimit = normalizedValue

        context.saveGState()
        if isEmphasized {
            context.setShadow(
                offset: .zero,
                blur: 4,
                color: VTXEditorControlTheme.accentGold.withAlphaComponent(0.42).cgColor
            )
        }
        context.setLineCap(.round)
        context.setLineWidth(isEmphasized ? 2.4 : 2.1)

        for index in 0..<toothCount {
            let fraction = toothCount == 1 ? CGFloat(0) : CGFloat(index) / CGFloat(toothCount - 1)
            let angle = Self.startAngle + (fraction * Self.sweepAngle)
            let inner = point(center: center, radius: innerRadius, angle: angle)
            let outer = point(center: center, radius: outerRadius, angle: angle)
            let toothColor = Double(fraction) <= litLimit
                ? VTXEditorControlTheme.accentGold
                : VTXEditorControlTheme.accentGold.withAlphaComponent(0.15)

            context.setStrokeColor(toothColor.cgColor)
            context.move(to: inner)
            context.addLine(to: outer)
            context.strokePath()
        }
        context.restoreGState()
    }

    private func drawBody(in context: CGContext) {
        let minSide = max(CGFloat(1), min(bounds.width, bounds.height))
        let bodyDiameter = minSide * 0.58
        let collarRect = centeredRect(diameter: bodyDiameter, in: bounds)
        let capRect = collarRect.insetBy(dx: bodyDiameter * 0.18, dy: bodyDiameter * 0.18)

        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -2),
            blur: 5,
            color: NSColor.black.withAlphaComponent(0.70).cgColor
        )
        context.setFillColor(VTXEditorControlTheme.interactiveFieldBackground.cgColor)
        context.fillEllipse(in: collarRect)
        context.restoreGState()

        context.saveGState()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.16).cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: collarRect.insetBy(dx: 0.5, dy: 0.5))
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.75).cgColor)
        context.strokeEllipse(in: collarRect.insetBy(dx: 2, dy: 2))
        context.restoreGState()

        context.saveGState()
        context.setFillColor(VTXEditorControlTheme.recessedReadoutBackground.cgColor)
        context.fillEllipse(in: capRect)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.10).cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: capRect.insetBy(dx: 0.5, dy: 0.5))
        context.restoreGState()
    }

    private func drawIndicator(in context: CGContext) {
        let minSide = max(CGFloat(1), min(bounds.width, bounds.height))
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let grooveStart = point(center: center, radius: minSide * 0.105, angle: valueAngle)
        let grooveEnd = point(center: center, radius: minSide * 0.235, angle: valueAngle)
        let tipCenter = point(center: center, radius: minSide * 0.255, angle: valueAngle)
        let tipRadius = minSide * 0.038

        context.saveGState()
        context.setLineCap(.round)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.92).cgColor)
        context.setLineWidth(6)
        context.move(to: grooveStart)
        context.addLine(to: grooveEnd)
        context.strokePath()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.08).cgColor)
        context.setLineWidth(2)
        context.move(to: grooveStart)
        context.addLine(to: grooveEnd)
        context.strokePath()
        context.restoreGState()

        let tipRect = NSRect(
            x: tipCenter.x - tipRadius,
            y: tipCenter.y - tipRadius,
            width: tipRadius * 2,
            height: tipRadius * 2
        )
        context.saveGState()
        context.setShadow(
            offset: .zero,
            blur: 5,
            color: VTXEditorControlTheme.accentGold.withAlphaComponent(0.80).cgColor
        )
        context.setFillColor(VTXEditorControlTheme.accentGold.cgColor)
        context.fillEllipse(in: tipRect)
        context.restoreGState()
    }

    private func centeredRect(diameter: CGFloat, in rect: NSRect) -> NSRect {
        NSRect(
            x: rect.midX - (diameter * 0.5),
            y: rect.midY - (diameter * 0.5),
            width: diameter,
            height: diameter
        )
    }

    private func point(center: CGPoint, radius: CGFloat, angle: CGFloat) -> CGPoint {
        CGPoint(
            x: center.x + (cos(angle) * radius),
            y: center.y + (sin(angle) * radius)
        )
    }

    private static let startAngle = CGFloat.pi * 1.25
    private static let sweepAngle = -CGFloat.pi * 1.5
}

/// Horizontal pan slider normalized from -1.0 left to +1.0 right with a snapping center detent.
final class VTXEditorPanSliderControl: NSControl {
    let minimumValue: Double = -1
    let maximumValue: Double = 1

    var value: Double {
        get { storedValue }
        set { setValue(newValue) }
    }

    var normalizedValue: Double {
        get { (storedValue + 1) * 0.5 }
        set {
            let clamped = min(max(newValue, 0), 1)
            setValue((clamped * 2) - 1)
        }
    }

    var centerDetentThreshold: Double {
        didSet {
            centerDetentThreshold = min(max(centerDetentThreshold, 0), 1)
            setValue(storedValue)
        }
    }

    var snapsToCenter: Bool {
        didSet { setValue(storedValue) }
    }

    var showsCenteredIndicator: Bool {
        didSet { needsDisplay = true }
    }

    var isCentered: Bool {
        abs(storedValue) <= Double.ulpOfOne
    }

    override var isEnabled: Bool {
        didSet { needsDisplay = true }
    }

    override var doubleValue: Double {
        get { value }
        set { value = newValue }
    }

    private var storedValue: Double
    private var didChangeDuringTracking = false

    init(
        value: Double = 0,
        centerDetentThreshold: Double = 0.05,
        snapsToCenter: Bool = true,
        showsCenteredIndicator: Bool = true
    ) {
        self.centerDetentThreshold = min(max(centerDetentThreshold, 0), 1)
        self.snapsToCenter = snapsToCenter
        self.showsCenteredIndicator = showsCenteredIndicator
        self.storedValue = 0
        super.init(frame: NSRect(origin: .zero, size: VTXEditorControlMetrics.panSliderControlSize))
        configureControl()
        setValue(value)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        VTXEditorControlMetrics.panSliderControlSize
    }

    /// Sets the pan value, clamps it to -1...+1, applies center snapping by default, and optionally sends the control action.
    @discardableResult
    func setValue(
        _ newValue: Double,
        sendAction: Bool = false,
        applyCenterDetent: Bool = true
    ) -> Bool {
        let nextValue = clamped(newValue, applyCenterDetent: applyCenterDetent)
        guard abs(nextValue - storedValue) > Double.ulpOfOne else {
            return false
        }

        storedValue = nextValue
        needsDisplay = true
        if sendAction {
            self.sendAction(action, to: target)
        }
        return true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        isEnabled
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        didChangeDuringTracking = updateValue(from: event, sendAction: isContinuous)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled else { return }
        didChangeDuringTracking = updateValue(from: event, sendAction: isContinuous) || didChangeDuringTracking
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled else { return }
        didChangeDuringTracking = updateValue(from: event, sendAction: isContinuous) || didChangeDuringTracking
        if !isContinuous, didChangeDuringTracking {
            sendAction(action, to: target)
        }
        didChangeDuringTracking = false
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        let trackRect = sliderTrackRect(in: bounds)
        let centerX = trackRect.midX
        let thumbX = trackRect.minX + (CGFloat(normalizedValue) * trackRect.width)
        let centered = isCentered

        context.saveGState()
        context.setAlpha(isEnabled ? 1 : 0.38)
        drawTrack(trackRect, in: context)
        drawFill(trackRect: trackRect, centerX: centerX, thumbX: thumbX, in: context)
        drawCenterDetent(trackRect: trackRect, centered: centered, in: context)
        drawThumb(centerX: thumbX, trackRect: trackRect, in: context)
        if showsCenteredIndicator {
            drawCenteredIndicator(isOn: centered, in: context)
        }
        context.restoreGState()
    }

    private func configureControl() {
        translatesAutoresizingMaskIntoConstraints = false
        cell = NSActionCell()
        isContinuous = true
        wantsLayer = true
        widthAnchor.constraint(equalToConstant: VTXEditorControlMetrics.panSliderControlSize.width).isActive = true
        heightAnchor.constraint(equalToConstant: VTXEditorControlMetrics.panSliderControlSize.height).isActive = true
    }

    @discardableResult
    private func updateValue(from event: NSEvent, sendAction: Bool) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        let trackRect = sliderTrackRect(in: bounds)
        guard trackRect.width > 0 else { return false }

        let normalized = min(max((point.x - trackRect.minX) / trackRect.width, 0), 1)
        return setValue((Double(normalized) * 2) - 1, sendAction: sendAction)
    }

    private func clamped(_ candidate: Double, applyCenterDetent: Bool) -> Double {
        let finiteValue = candidate.isFinite ? candidate : 0
        var clampedValue = min(max(finiteValue, minimumValue), maximumValue)
        if snapsToCenter, applyCenterDetent, abs(clampedValue) <= centerDetentThreshold {
            clampedValue = 0
        }
        return clampedValue
    }

    private func sliderTrackRect(in rect: NSRect) -> NSRect {
        let inset: CGFloat = 8
        let height: CGFloat = 10
        let y = floor((rect.height - height) * 0.5) - 1
        return NSRect(
            x: rect.minX + inset,
            y: rect.minY + max(4, y),
            width: max(1, rect.width - (inset * 2)),
            height: height
        )
    }

    private func drawTrack(_ rect: NSRect, in context: CGContext) {
        let path = roundedPath(rect, radius: rect.height * 0.5)
        let insetPath = roundedPath(rect.insetBy(dx: 0.5, dy: 0.5), radius: rect.height * 0.5)

        context.saveGState()
        context.setFillColor(NSColor.black.withAlphaComponent(0.64).cgColor)
        context.addPath(path)
        context.fillPath()
        context.setStrokeColor(VTXEditorControlTheme.mutedGoldBorderSubtle.cgColor)
        context.setLineWidth(1)
        context.addPath(insetPath)
        context.strokePath()
        context.restoreGState()
    }

    private func drawFill(trackRect: NSRect, centerX: CGFloat, thumbX: CGFloat, in context: CGContext) {
        let fillMinX = min(centerX, thumbX)
        let fillWidth = abs(thumbX - centerX)
        guard fillWidth > 0.5 else { return }

        let fillRect = NSRect(x: fillMinX, y: trackRect.minY, width: fillWidth, height: trackRect.height)
        context.saveGState()
        context.setFillColor(VTXEditorControlTheme.accentGold.withAlphaComponent(0.16).cgColor)
        context.addPath(roundedPath(fillRect, radius: trackRect.height * 0.5))
        context.fillPath()
        context.restoreGState()
    }

    private func drawCenterDetent(trackRect: NSRect, centered: Bool, in context: CGContext) {
        let centerX = trackRect.midX
        let tickRect = NSRect(x: centerX - 0.5, y: trackRect.minY - 4, width: 1, height: trackRect.height + 8)
        let detentRect = NSRect(x: centerX - 5, y: trackRect.midY - 5, width: 10, height: 10)

        context.saveGState()
        if centered {
            context.setShadow(
                offset: .zero,
                blur: 6,
                color: VTXEditorControlTheme.accentGold.withAlphaComponent(0.80).cgColor
            )
        }
        let tickColor = centered ? VTXEditorControlTheme.accentGold : VTXEditorControlTheme.mutedGoldBorderMedium
        context.setFillColor(tickColor.cgColor)
        context.fill(tickRect)
        context.setFillColor(VTXEditorControlTheme.accentGold.withAlphaComponent(centered ? 0.22 : 0.10).cgColor)
        context.fillEllipse(in: detentRect)
        context.restoreGState()
    }

    private func drawThumb(centerX: CGFloat, trackRect: NSRect, in context: CGContext) {
        let thumbRect = NSRect(x: centerX - 6.5, y: trackRect.midY - 10, width: 13, height: 20)
        let grooveRect = NSRect(x: thumbRect.midX - 1, y: thumbRect.minY + 3, width: 2, height: thumbRect.height - 6)

        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -1),
            blur: 2,
            color: NSColor.black.withAlphaComponent(0.62).cgColor
        )
        context.setFillColor(VTXEditorControlTheme.interactiveFieldBackground.cgColor)
        context.addPath(roundedPath(thumbRect, radius: 3))
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.82).cgColor)
        context.setLineWidth(1)
        context.addPath(roundedPath(thumbRect.insetBy(dx: 0.5, dy: 0.5), radius: 3))
        context.strokePath()
        context.setFillColor(VTXEditorControlTheme.accentGold.withAlphaComponent(0.60).cgColor)
        context.addPath(roundedPath(grooveRect, radius: 1))
        context.fillPath()
        context.restoreGState()
    }

    private func drawCenteredIndicator(isOn: Bool, in context: CGContext) {
        let diameter: CGFloat = 7
        let rect = NSRect(
            x: bounds.maxX - diameter - 2,
            y: bounds.maxY - diameter - 2,
            width: diameter,
            height: diameter
        )

        context.saveGState()
        if isOn {
            context.setShadow(
                offset: .zero,
                blur: 6,
                color: VTXEditorControlTheme.accentGold.withAlphaComponent(0.80).cgColor
            )
            context.setFillColor(VTXEditorControlTheme.accentGold.cgColor)
        } else {
            context.setFillColor(NSColor(srgbRed: 0x2A / 255.0, green: 0x24 / 255.0, blue: 0x10 / 255.0, alpha: 1.0).cgColor)
        }
        context.fillEllipse(in: rect)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.70).cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: rect.insetBy(dx: 0.5, dy: 0.5))
        context.restoreGState()
    }

    private func roundedPath(_ rect: NSRect, radius: CGFloat) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
}
