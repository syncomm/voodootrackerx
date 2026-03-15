// Owns the logo panel container, including its white panel background and centered logo image.
// It does not own window layout, state wiring, or any control-panel/tracker behavior.
import AppKit

final class LogoPanelView: NSBox {
    private let theme: TrackerTheme

    init(frame frameRect: NSRect, theme: TrackerTheme = .legacyDark) {
        self.theme = theme
        super.init(frame: frameRect)
        boxType = .custom
        borderWidth = 0
        fillColor = .white
        contentViewMargins = .zero
        buildLogoPresentation()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildLogoPresentation() {
        if let logoImage = loadBundledLogoImage() {
            let maxLogoWidth = min(bounds.width - TrackerThemeMetrics.LogoLayout.horizontalPadding, TrackerThemeMetrics.LogoLayout.maximumWidth)
            let logoAspect = logoImage.size.width > 0 ? (logoImage.size.height / logoImage.size.width) : 0.15
            var logoWidth = maxLogoWidth
            var logoHeight = logoWidth * logoAspect
            let maxLogoHeight = bounds.height - TrackerThemeMetrics.LogoLayout.verticalPadding
            if logoHeight > maxLogoHeight, logoAspect > 0 {
                logoHeight = maxLogoHeight
                logoWidth = logoHeight / logoAspect
            }

            let imageView = NSImageView(frame: NSRect(
                x: (bounds.width - logoWidth) * 0.5,
                y: (bounds.height - logoHeight) * 0.5,
                width: logoWidth,
                height: logoHeight
            ))
            imageView.autoresizingMask = [.minXMargin, .maxXMargin]
            imageView.image = logoImage
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.wantsLayer = true
            imageView.layer?.magnificationFilter = .nearest
            imageView.layer?.minificationFilter = .nearest
            addSubview(imageView)
            return
        }

        let fallbackTitle = NSTextField(labelWithString: "VoodooTracker X")
        fallbackTitle.frame = bounds.insetBy(dx: 8, dy: 4)
        fallbackTitle.autoresizingMask = [.width, .height]
        fallbackTitle.alignment = .center
        fallbackTitle.font = TrackerThemeFonts.fallbackLogo
        fallbackTitle.textColor = theme.text
        addSubview(fallbackTitle)
    }

    private func loadBundledLogoImage() -> NSImage? {
        if let svg = Bundle.main.url(forResource: "vtx-logo", withExtension: "svg"),
           let image = NSImage(contentsOf: svg) {
            return image
        }
        if let fallback = Bundle.main.url(forResource: "vtx-logo", withExtension: "png"),
           let image = NSImage(contentsOf: fallback) {
            return image
        }
        return nil
    }
}
