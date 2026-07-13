import AppKit
import XCTest

@MainActor
final class EditorControlPrimitivesTests: XCTestCase {
    func testEditorThemeTokensMatchDesignVocabulary() {
        assertColor(VTXEditorControlTheme.windowBackground, matchesSRGB: (0x1E, 0x1E, 0x1E, 1.0))
        assertColor(VTXEditorControlTheme.panelSurface, matchesSRGB: (0x25, 0x25, 0x26, 1.0))
        assertColor(VTXEditorControlTheme.recessedReadoutBackground, matchesSRGB: (0x18, 0x18, 0x19, 1.0))
        assertColor(VTXEditorControlTheme.interactiveFieldBackground, matchesSRGB: (0x1C, 0x1C, 0x1D, 1.0))
        assertColor(VTXEditorControlTheme.accentGold, matchesSRGB: (0xC9, 0xA7, 0x4A, 1.0))
        assertColor(VTXEditorControlTheme.mutedGoldBorderStrong, matchesSRGB: (0xC9, 0xA7, 0x4A, 0.55))
        assertColor(VTXEditorControlTheme.mutedGoldBorderMedium, matchesSRGB: (0xC9, 0xA7, 0x4A, 0.38))
        assertColor(VTXEditorControlTheme.mutedGoldBorderSubtle, matchesSRGB: (0xC9, 0xA7, 0x4A, 0.22))
        assertColor(VTXEditorControlTheme.warmValueText, matchesSRGB: (0xE8, 0xD8, 0xA0, 1.0))
        assertColor(VTXEditorControlTheme.playActiveGreen, matchesSRGB: (0x4D, 0xB8, 0x68, 1.0))
        assertColor(VTXEditorControlTheme.indigoSelection, matchesSRGB: (0x46, 0x54, 0x7D, 0.55))
        assertColor(VTXEditorControlTheme.indicatorLEDRed, matchesSRGB: (0xE0, 0x47, 0x3A, 1.0))
        assertColor(VTXEditorControlTheme.dangerRed, matchesSRGB: (0xCC, 0x5A, 0x50, 1.0))
    }

    func testPanelLabelFactoryAppliesUppercaseMonospaceGoldStyle() {
        let label = VTXEditorControlFactory.makePanelLabel("Envelope")

        XCTAssertEqual(label.stringValue, "ENVELOPE")
        XCTAssertFalse(label.isEditable)
        XCTAssertEqual(label.font, VTXEditorControlFonts.panelLabel)
        assertColor(label.textColor, matches: VTXEditorControlTheme.panelLabelText)
    }

    func testSegmentReadoutAppliesTextAndRecessedChrome() {
        let readout = VTXEditorControlFactory.makeSegmentReadout(value: "I01", fixedWidth: 42)

        XCTAssertEqual(readout.stringValue, "I01")
        XCTAssertEqual(readout.fixedWidth, 42)
        XCTAssertNil(readout.minimumWidth)
        XCTAssertFalse(readout.isEditable)
        XCTAssertTrue(readout.isSelectable)
        XCTAssertEqual(readout.alignment, .center)
        XCTAssertEqual(readout.cell?.alignment, .center)
        assertColor(readout.textColor, matches: VTXEditorControlTheme.warmValueText)
        assertColor(readout.layer?.backgroundColor, matches: VTXEditorControlTheme.recessedReadoutBackground)
        assertColor(readout.layer?.borderColor, matches: VTXEditorControlTheme.mutedGoldBorderSubtle)
    }

    func testSegmentReadoutSupportsMinimumWidth() {
        let readout = VTXEditorControlFactory.makeSegmentReadout(value: "LOOP", minimumWidth: 56, alignment: .right)

        XCTAssertNil(readout.fixedWidth)
        XCTAssertEqual(readout.minimumWidth, 56)
        XCTAssertEqual(readout.alignment, .right)
        XCTAssertTrue(readout.constraints.contains { constraint in
            constraint.firstAttribute == .width &&
                constraint.relation == .greaterThanOrEqual &&
                abs(constraint.constant - 56) < 0.001
        })
    }

    func testIndicatorLEDStateChangesAreRepresentedWithoutButtonBehavior() {
        let led = VTXEditorControlFactory.makeIndicatorLED(state: .off, diameter: 9)

        XCTAssertEqual(led.state, .off)
        XCTAssertEqual(led.intrinsicContentSize, NSSize(width: 9, height: 9))
        XCTAssertNil(led.hitTest(NSPoint(x: 4, y: 4)))
        assertColor(led.fillColor, matches: VTXEditorControlTheme.ledOffFill)

        led.state = .redActive
        XCTAssertEqual(led.state, .redActive)
        assertColor(led.fillColor, matches: VTXEditorControlTheme.indicatorLEDRed)

        led.state = .amberActive
        XCTAssertEqual(led.state, .amberActive)
        assertColor(led.fillColor, matches: VTXEditorControlTheme.amberLED)
    }

    func testEditorButtonFactoryCreatesExpectedRolesAndChrome() {
        let normal = VTXEditorControlFactory.makeButton(title: "insert", role: .normal, fixedWidth: 64)
        let selected = VTXEditorControlFactory.makeButton(title: "vol", role: .selected)
        let active = VTXEditorControlFactory.makeButton(title: "play", role: .activePlay)
        let danger = VTXEditorControlFactory.makeButton(title: "clear", role: .danger)

        XCTAssertEqual(normal.title, "INSERT")
        XCTAssertEqual(normal.editorRole, .normal)
        XCTAssertEqual(normal.bezelStyle, .shadowlessSquare)
        XCTAssertFalse(normal.isBordered)
        assertColor(normal.layer?.backgroundColor, matches: VTXEditorButtonRole.normal.backgroundColor)
        assertColor(normal.layer?.borderColor, matches: VTXEditorButtonRole.normal.borderColor)

        XCTAssertEqual(selected.title, "VOL")
        XCTAssertEqual(selected.editorRole, .selected)
        assertColor(selected.layer?.backgroundColor, matches: VTXEditorButtonRole.selected.backgroundColor)
        assertColor(selected.layer?.borderColor, matches: VTXEditorButtonRole.selected.borderColor)

        XCTAssertEqual(active.title, "PLAY")
        XCTAssertEqual(active.editorRole, .activePlay)
        assertColor(active.layer?.backgroundColor, matches: VTXEditorButtonRole.activePlay.backgroundColor)
        assertColor(active.layer?.borderColor, matches: VTXEditorButtonRole.activePlay.borderColor)

        XCTAssertEqual(danger.title, "CLEAR")
        XCTAssertEqual(danger.editorRole, .danger)
        assertColor(danger.layer?.backgroundColor, matches: VTXEditorButtonRole.danger.backgroundColor)
        assertColor(danger.layer?.borderColor, matches: VTXEditorButtonRole.danger.borderColor)
    }

    func testKnobDefaultRangeAndValueClamping() {
        let knob = VTXEditorControlFactory.makeKnobControl(value: 4, minimumValue: 2, maximumValue: 6)

        XCTAssertEqual(knob.minimumValue, 2)
        XCTAssertEqual(knob.maximumValue, 6)
        XCTAssertEqual(knob.value, 4, accuracy: 0.0001)
        XCTAssertEqual(knob.doubleValue, 4, accuracy: 0.0001)
        XCTAssertEqual(knob.normalizedValue, 0.5, accuracy: 0.0001)

        knob.value = 12
        XCTAssertEqual(knob.value, 6, accuracy: 0.0001)
        XCTAssertEqual(knob.normalizedValue, 1, accuracy: 0.0001)

        knob.value = -5
        XCTAssertEqual(knob.value, 2, accuracy: 0.0001)
        XCTAssertEqual(knob.normalizedValue, 0, accuracy: 0.0001)

        knob.normalizedValue = 0.25
        XCTAssertEqual(knob.value, 3, accuracy: 0.0001)
    }

    func testKnobEmphasisAndEnabledStateAreRepresented() {
        let knob = VTXEditorControlFactory.makeKnobControl()

        XCTAssertFalse(knob.isEmphasized)
        XCTAssertTrue(knob.isEnabled)
        XCTAssertEqual(knob.intrinsicContentSize, VTXEditorControlMetrics.knobControlSize)

        knob.isEmphasized = true
        knob.isEnabled = false

        XCTAssertTrue(knob.isEmphasized)
        XCTAssertFalse(knob.isEnabled)
        XCTAssertEqual(knob.intrinsicContentSize, VTXEditorControlMetrics.knobControlSize)
    }

    func testKnobCanSendActionOnValueChange() {
        let knob = VTXEditorControlFactory.makeKnobControl()
        let recorder = EditorControlActionRecorder()
        knob.target = recorder
        knob.action = #selector(EditorControlActionRecorder.record(_:))

        XCTAssertTrue(knob.setValue(0.5, sendAction: true))
        XCTAssertEqual(recorder.count, 1)
        XCTAssertTrue(recorder.lastSender === knob)

        XCTAssertFalse(knob.setValue(0.5, sendAction: true))
        XCTAssertEqual(recorder.count, 1)

        knob.value = 0.75
        XCTAssertEqual(recorder.count, 1)
    }

    func testPanSliderDefaultRangeAndValueClamping() {
        let slider = VTXEditorControlFactory.makePanSliderControl()

        XCTAssertEqual(slider.minimumValue, -1)
        XCTAssertEqual(slider.maximumValue, 1)
        XCTAssertEqual(slider.value, 0, accuracy: 0.0001)
        XCTAssertEqual(slider.doubleValue, 0, accuracy: 0.0001)
        XCTAssertEqual(slider.normalizedValue, 0.5, accuracy: 0.0001)
        XCTAssertTrue(slider.isCentered)

        slider.value = 2
        XCTAssertEqual(slider.value, 1, accuracy: 0.0001)
        XCTAssertEqual(slider.normalizedValue, 1, accuracy: 0.0001)

        slider.value = -2
        XCTAssertEqual(slider.value, -1, accuracy: 0.0001)
        XCTAssertEqual(slider.normalizedValue, 0, accuracy: 0.0001)

        slider.normalizedValue = 0.75
        XCTAssertEqual(slider.value, 0.5, accuracy: 0.0001)
    }

    func testPanSliderCenterDetentSnappingAndIndicatorState() {
        let slider = VTXEditorControlFactory.makePanSliderControl(value: 0.4, centerDetentThreshold: 0.08)

        XCTAssertEqual(slider.value, 0.4, accuracy: 0.0001)
        XCTAssertFalse(slider.isCentered)
        XCTAssertTrue(slider.showsCenteredIndicator)

        slider.value = 0.05
        XCTAssertEqual(slider.value, 0, accuracy: 0.0001)
        XCTAssertTrue(slider.isCentered)

        slider.setValue(-0.07)
        XCTAssertEqual(slider.value, 0, accuracy: 0.0001)
        XCTAssertTrue(slider.isCentered)

        slider.setValue(0.09)
        XCTAssertEqual(slider.value, 0.09, accuracy: 0.0001)
        XCTAssertFalse(slider.isCentered)

        slider.snapsToCenter = false
        slider.value = 0.03
        XCTAssertEqual(slider.value, 0.03, accuracy: 0.0001)
        XCTAssertFalse(slider.isCentered)

        slider.showsCenteredIndicator = false
        XCTAssertFalse(slider.showsCenteredIndicator)
    }

    func testPanSliderCanSendActionOnValueChange() {
        let slider = VTXEditorControlFactory.makePanSliderControl()
        let recorder = EditorControlActionRecorder()
        slider.target = recorder
        slider.action = #selector(EditorControlActionRecorder.record(_:))

        XCTAssertTrue(slider.setValue(0.35, sendAction: true))
        XCTAssertEqual(recorder.count, 1)
        XCTAssertTrue(recorder.lastSender === slider)

        XCTAssertFalse(slider.setValue(0.35, sendAction: true))
        XCTAssertEqual(recorder.count, 1)

        slider.value = -0.4
        XCTAssertEqual(recorder.count, 1)
    }

    func testPanSliderNonContinuousTrackingCommitsOnceOnMouseUp() throws {
        let slider = VTXEditorControlFactory.makePanSliderControl()
        slider.frame = NSRect(x: 0, y: 0, width: 170, height: 32)
        slider.isContinuous = false
        let recorder = EditorControlActionRecorder()
        slider.target = recorder
        slider.action = #selector(EditorControlActionRecorder.record(_:))
        let event: (NSEvent.EventType, CGFloat) throws -> NSEvent = { type, x in
            try XCTUnwrap(NSEvent.mouseEvent(
                with: type,
                location: NSPoint(x: x, y: 16),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            ))
        }

        slider.mouseDown(with: try event(.leftMouseDown, 30))
        slider.mouseDragged(with: try event(.leftMouseDragged, 90))
        slider.mouseDragged(with: try event(.leftMouseDragged, 150))
        XCTAssertEqual(recorder.count, 0)
        slider.mouseUp(with: try event(.leftMouseUp, 150))
        XCTAssertEqual(recorder.count, 1)
    }

    private func assertColor(
        _ actual: NSColor?,
        matches expected: NSColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual else {
            XCTFail("Missing color", file: file, line: line)
            return
        }
        assertColor(actual, matchesSRGB: expected.rgbaSRGBComponents(), file: file, line: line)
    }

    private func assertColor(
        _ actual: CGColor?,
        matches expected: NSColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual,
              let actualColor = NSColor(cgColor: actual) else {
            XCTFail("Missing color", file: file, line: line)
            return
        }
        assertColor(actualColor, matchesSRGB: expected.rgbaSRGBComponents(), file: file, line: line)
    }

    private func assertColor(
        _ actual: NSColor,
        matchesSRGB expected: (red: Int, green: Int, blue: Int, alpha: CGFloat),
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actualColor = actual.usingColorSpace(.sRGB) else {
            XCTFail("Missing sRGB color", file: file, line: line)
            return
        }

        XCTAssertEqual(actualColor.redComponent, CGFloat(expected.red) / 255.0, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualColor.greenComponent, CGFloat(expected.green) / 255.0, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualColor.blueComponent, CGFloat(expected.blue) / 255.0, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualColor.alphaComponent, expected.alpha, accuracy: 0.001, file: file, line: line)
    }
}

private final class EditorControlActionRecorder: NSObject {
    var count = 0
    weak var lastSender: AnyObject?

    @objc func record(_ sender: Any?) {
        count += 1
        lastSender = sender as AnyObject?
    }
}

private extension NSColor {
    func rgbaSRGBComponents() -> (red: Int, green: Int, blue: Int, alpha: CGFloat) {
        guard let color = usingColorSpace(.sRGB) else {
            return (0, 0, 0, 0)
        }
        return (
            red: Int(round(color.redComponent * 255)),
            green: Int(round(color.greenComponent * 255)),
            blue: Int(round(color.blueComponent * 255)),
            alpha: color.alphaComponent
        )
    }
}
