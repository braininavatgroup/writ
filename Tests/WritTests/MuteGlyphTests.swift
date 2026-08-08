import AppKit
import XCTest
@testable import Writ

/// The muted menu bar glyph must actually be red.
///
/// It shipped black. A template image is stencilled in the menu bar's own
/// colour and ignores `contentTintColor`, so asking for red that way silently
/// produced a black mic.slash — indistinguishable at a glance from the normal
/// icon, which defeats the entire point of showing mute state.
@MainActor
final class MuteGlyphTests: XCTestCase {

    private func reddestOpaquePixel(of image: NSImage) -> NSColor? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        var best: NSColor?
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      c.alphaComponent > 0.5 else { continue }
                if c.redComponent > (best?.redComponent ?? -1) { best = c }
            }
        }
        return best
    }

    func testMutedGlyphRendersRed() throws {
        let image = try XCTUnwrap(StatusItemController.mutedGlyph())
        XCTAssertFalse(image.isTemplate,
                       "a template image is stencilled by the menu bar and cannot be red")

        let colour = try XCTUnwrap(reddestOpaquePixel(of: image))
        XCTAssertGreaterThan(colour.redComponent, 0.6)
        XCTAssertLessThan(colour.greenComponent, 0.5)
        XCTAssertLessThan(colour.blueComponent, 0.5)
    }

    /// The regression itself, asserted directly: the approach that shipped black
    /// must still be black, so this test is meaningful rather than tautological.
    func testTemplateVariantWouldBeBlack() throws {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let image = try XCTUnwrap(
            NSImage(systemSymbolName: "mic.slash.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(config))
        image.isTemplate = true

        let colour = try XCTUnwrap(reddestOpaquePixel(of: image))
        XCTAssertLessThan(colour.redComponent, 0.2,
                          "if this goes red, template images now honour tint and the "
                          + "muted glyph could be simplified")
    }
}
