import AppKit
import Testing
@testable import HermesDesktop

@MainActor
struct TerminalViewHostTests {
    @Test
    func terminalBackgroundColorIsClearWhenBackgroundImageIsActive() throws {
        let expectedBackground = TerminalThemeColor(hex: 0x112233)
        let preference = TerminalThemePreference(style: .paper)
            .updatingBackgroundColor(expectedBackground)
            .updatingForegroundColor(TerminalThemeColor(hex: 0xEEDFCC))
        let hostView = TerminalHostView(frame: .zero)

        hostView.apply(
            appearance: preference.resolvedAppearance,
            backgroundImageActive: true
        )

        assertColorIsClear(hostView.terminalView.nativeBackgroundColor)
        assertColorIsClear(NSColor(cgColor: try #require(hostView.layer?.backgroundColor)))
    }

    private func assertColorIsClear(_ nsColor: NSColor?) {
        let color = nsColor?.usingColorSpace(.deviceRGB)

        #expect(color?.alphaComponent == 0)
    }
}
