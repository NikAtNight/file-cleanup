import AppKit
import SwiftUI

/// Adaptive colors shared by the main window and rule editor.
enum Theme {
    static func color(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
    static let accent = color(0x146657, 0x78D7BC)
    static let canvas = color(0xF5F7F2, 0x151B1A)
    static let surface = color(0xFFFFFF, 0x202826)
    static let sidebar = color(0xFFFFFF, 0x19211F)
    static let border = color(0xE7EBE5, 0x35403C)
    static let warning = color(0x944714, 0xF2B67C)
}

extension View {
    func card() -> some View {
        self.padding(20).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1))
    }
}
