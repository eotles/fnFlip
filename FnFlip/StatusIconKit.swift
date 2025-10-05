import AppKit
import SwiftUI

public enum IconState {
    case off
    case on
    case workingFromOff   // off → on look, outline pill, rotating filled arrows
    case workingFromOn    // on  → off look, filled pill, rotating cutout arrows
}

public struct IconStyle {
    public var size: NSSize = NSSize(width: 24, height: 20)
    public var cornerRadius: CGFloat = 6
    public var lineWidth: CGFloat = 1.0

    // text glyph
    public var glyphText: String = "fn"
    public var glyphPointSize: CGFloat = 13
    public var glyphFontWeight: NSFont.Weight = .semibold
    public var glyphFontName: String? = nil
    public var glyphLetterSpacing: CGFloat = 0
    public var baselineAdjust: CGFloat = 0

    // arrows
    public var arrowPointSize: CGFloat = 13

    public var padding: CGFloat = 3.0
    public var outlineUsesTemplateTint: Bool = true
    public var fillUsesTemplateTint: Bool = true

    // animation
    public var spinsPerSecond: CGFloat = 1.0
    public var frameRate: CGFloat = 30.0

    public init() {}
}

public final class StatusIconController {

    public init(style: IconStyle = IconStyle()) {
        self.style = style
    }

    public var style: IconStyle

    // animation state
    private var timer: Timer?
    private var rotationAngle: CGFloat = 0
    private weak var rotatingButton: NSStatusBarButton?
    private var workingState: IconState?

    // Apply a state to a status bar button. Starts or stops spinner as needed.
    public func apply(to button: NSStatusBarButton, state: IconState) {
        rotatingButton = button

        switch state {
        case .workingFromOff, .workingFromOn:
            workingState = state
            startSpinner()
        case .off, .on:
            workingState = nil
            stopSpinner()
            button.image = image(for: state, angle: 0)
        }
    }

    // Build the icon image for a state. Angle used only for working states.
    public func image(for state: IconState, angle: CGFloat = 0) -> NSImage? {
        switch state {
        case .off:              return offIcon(style: style)
        case .on:               return onIcon(style: style)
        case .workingFromOff:   return workingFromOffIcon(style: style, angle: angle)
        case .workingFromOn:    return workingFromOnIcon(style: style, angle: angle)
        }
    }

    // MARK: internals

    private func arrowsSymbol() -> NSImage? {
        NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Working")
    }

    private func glyphTargetRect(in overall: NSRect, padding: CGFloat) -> NSRect {
        overall.insetBy(dx: padding, dy: padding)
    }

    private func drawSymbol(_ sym: NSImage, in rect: NSRect, operation: NSCompositingOperation, angleDegrees: CGFloat) {
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            sym.draw(in: rect, from: .zero, operation: operation, fraction: 1.0)
            return
        }
        ctx.saveGState()
        ctx.translateBy(x: rect.midX, y: rect.midY)
        ctx.rotate(by: angleDegrees * .pi / 180.0)
        let drawRect = NSRect(x: -rect.width/2, y: -rect.height/2, width: rect.width, height: rect.height)
        sym.draw(in: drawRect, from: .zero, operation: operation, fraction: 1.0)
        ctx.restoreGState()
    }

    // Off: outline pill + “fn” in foreground
    private func offIcon(style: IconStyle) -> NSImage? {
        let img = NSImage(size: style.size)
        img.lockFocus()

        let rect = NSRect(x: 0.5, y: 0.5, width: style.size.width - 1, height: style.size.height - 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: style.cornerRadius, yRadius: style.cornerRadius)
        NSColor.black.setStroke()
        path.lineWidth = style.lineWidth
        path.stroke()

        let textImage = makeTextGlyph(
            text: style.glyphText,
            pointSize: style.glyphPointSize,
            weight: style.glyphFontWeight,
            fontName: style.glyphFontName,
            letterSpacing: style.glyphLetterSpacing
        )
        let padRect = NSRect(origin: .zero, size: style.size).insetBy(dx: style.padding, dy: style.padding)
        var fit = aspectFitRect(imageSize: textImage.size, in: padRect)
        fit.origin.y += style.baselineAdjust
        NSColor.black.set()
        textImage.draw(in: fit, from: .zero, operation: .sourceOver, fraction: 1.0)

        img.unlockFocus()
        img.isTemplate = style.outlineUsesTemplateTint
        return img
    }

    // On: filled pill + “fn” cutout
    private func onIcon(style: IconStyle) -> NSImage? {
        let img = NSImage(size: style.size)
        img.lockFocus()

        let rect = NSRect(x: 0, y: 0, width: style.size.width, height: style.size.height)
        let pillPath = NSBezierPath(roundedRect: rect, xRadius: style.cornerRadius, yRadius: style.cornerRadius)
        NSColor.black.setFill()
        pillPath.fill()

        let textImage = makeTextGlyph(
            text: style.glyphText,
            pointSize: style.glyphPointSize,
            weight: style.glyphFontWeight,
            fontName: style.glyphFontName,
            letterSpacing: style.glyphLetterSpacing
        )
        let padRect = rect.insetBy(dx: style.padding, dy: style.padding)
        var fit = aspectFitRect(imageSize: textImage.size, in: padRect)
        fit.origin.y += style.baselineAdjust
        textImage.draw(in: fit, from: .zero, operation: .destinationOut, fraction: 1.0)

        img.unlockFocus()
        img.isTemplate = style.fillUsesTemplateTint
        return img
    }

    // Working from OFF: outline pill + rotating solid arrows
    private func workingFromOffIcon(style: IconStyle, angle: CGFloat) -> NSImage? {
        let img = NSImage(size: style.size)
        img.lockFocus()

        let rect = NSRect(x: 0.5, y: 0.5, width: style.size.width - 1, height: style.size.height - 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: style.cornerRadius, yRadius: style.cornerRadius)
        NSColor.black.setStroke()
        path.lineWidth = style.lineWidth
        path.stroke()

        let cfg = NSImage.SymbolConfiguration(pointSize: style.arrowPointSize, weight: .regular)
        if let arrows = arrowsSymbol()?.withSymbolConfiguration(cfg), arrows.size != .zero {
            let target = glyphTargetRect(in: NSRect(origin: .zero, size: style.size), padding: style.padding)
            let fit = aspectFitRect(imageSize: arrows.size, in: target)
            NSColor.black.set()
            drawSymbol(arrows, in: fit, operation: .sourceOver, angleDegrees: angle)
        }

        img.unlockFocus()
        img.isTemplate = style.outlineUsesTemplateTint
        return img
    }

    // Working from ON: filled pill + rotating arrows cut out
    private func workingFromOnIcon(style: IconStyle, angle: CGFloat) -> NSImage? {
        let img = NSImage(size: style.size)
        img.lockFocus()

        let rect = NSRect(x: 0, y: 0, width: style.size.width, height: style.size.height)
        let pillPath = NSBezierPath(roundedRect: rect, xRadius: style.cornerRadius, yRadius: style.cornerRadius)
        NSColor.black.setFill()
        pillPath.fill()

        let cfg = NSImage.SymbolConfiguration(pointSize: style.arrowPointSize, weight: .regular)
        if let arrows = arrowsSymbol()?.withSymbolConfiguration(cfg), arrows.size != .zero {
            let target = glyphTargetRect(in: rect, padding: style.padding)
            let fit = aspectFitRect(imageSize: arrows.size, in: target)
            drawSymbol(arrows, in: fit, operation: .destinationOut, angleDegrees: angle)
        }

        img.unlockFocus()
        img.isTemplate = style.fillUsesTemplateTint
        return img
    }

    // timer spinner, rotates only the arrows
    private func startSpinner() {
        stopSpinner()
        rotationAngle = 0

        let stepPerFrame = style.spinsPerSecond * 360.0 / max(style.frameRate, 1)
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(1.0 / max(style.frameRate, 1)),
                                     repeats: true) { [weak self] _ in
            guard let self = self,
                  let button = self.rotatingButton,
                  let wState = self.workingState else { return }

            self.rotationAngle = fmod(self.rotationAngle + stepPerFrame, 360.0)
            button.image = self.image(for: wState, angle: self.rotationAngle)
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    private func stopSpinner() {
        timer?.invalidate()
        timer = nil
        rotationAngle = 0
    }
}

/// Aspect-fit a source image size into bounds.
public func aspectFitRect(imageSize: NSSize, in bounds: NSRect) -> NSRect {
    let iw = max(imageSize.width, 0.001)
    let ih = max(imageSize.height, 0.001)
    let iAR = iw / ih
    let bAR = bounds.width / max(bounds.height, 0.001)

    var w = bounds.width
    var h = bounds.height
    if iAR > bAR {
        h = w / iAR
    } else {
        w = h * iAR
    }
    return NSRect(x: bounds.midX - w/2, y: bounds.midY - h/2, width: w, height: h)
}

/// Render a short text glyph, like "fn", into an NSImage.
/// Color only matters when using it as a foreground. For cutouts the compositing op controls the result.
public func makeTextGlyph(
    text: String,
    pointSize: CGFloat,
    weight: NSFont.Weight,
    fontName: String? = nil,
    letterSpacing: CGFloat = 0,
    color: NSColor = .black
) -> NSImage {
    let font: NSFont = {
        if let fontName, let custom = NSFont(name: fontName, size: pointSize) {
            return custom
        } else {
            return NSFont.systemFont(ofSize: pointSize, weight: weight)
        }
    }()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center

    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .kern: letterSpacing,
        .paragraphStyle: paragraph
    ]

    let attr = NSAttributedString(string: text, attributes: attrs)
    var size = attr.size()
    size.width = ceil(size.width) + 1
    size.height = ceil(size.height) + 1

    let img = NSImage(size: size)
    img.lockFocus()
    NSColor.clear.setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
    attr.draw(in: NSRect(origin: .zero, size: size))
    img.unlockFocus()
    img.isTemplate = false
    return img
}


#if DEBUG
// Simple preview
private struct IconRowPreview: View {
    @State private var angle: Double = 0
    let controller = StatusIconController()

    var body: some View {
        let off = controller.image(for: .off) ?? NSImage()
        let on = controller.image(for: .on) ?? NSImage()
        let wOff = controller.image(for: .workingFromOff, angle: angle) ?? NSImage()
        let wOn  = controller.image(for: .workingFromOn,  angle: angle) ?? NSImage()

        VStack(spacing: 16) {
            HStack(spacing: 22) {
                VStack { Image(nsImage: off); Text("Off").font(.caption) }
                VStack { Image(nsImage: on); Text("On").font(.caption) }
                VStack { Image(nsImage: wOff); Text("WorkingFromOff").font(.caption2) }
                VStack { Image(nsImage: wOn);  Text("WorkingFromOn").font(.caption2) }
            }
            .padding(20)
            .background(Color(NSColor.windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .onAppear {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
        }
        .padding(20)
        .frame(width: 680)
    }
}

#Preview("Status Icons - All States") {
    IconRowPreview().preferredColorScheme(.dark)
}
#endif
