//
//  CalloutExtension.swift
//  MarkdownEngine
//
//  Obsidian-style `> [!type]` callouts as a blockquote specialization.
//  Not registered by default — embedders opt in via:
//
//      configuration.extensions = [CalloutExtension()]
//
//  Built-in `>` lines still classify as blockquotes (fenced extensions cannot
//  claim them). When this extension is registered, the styler restyles a
//  blockquote whose first content is `[!type]` as a tinted titled box:
//  markers hide while the caret is outside and reveal muted while editing.
//  The clean-copy path still emits a blockquote.
//

import AppKit
import Foundation

public struct CalloutExtension: MarkdownExtension {

    public static let identifier = "callout"

    public init() {}

    public var id: String { Self.identifier }

    public func contentAttributes(theme: MarkdownEditorTheme) -> [NSAttributedString.Key: Any] {
        [:]
    }

    public func html(childrenHTML: String) -> String {
        "<blockquote>\(childrenHTML)</blockquote>"
    }

    /// `[!type]` at the start of already-dequoted content, document coordinates.
    public static func marker(in ns: NSString, contentRange: NSRange) -> CalloutMarker? {
        guard contentRange.length >= 4 else { return nil }
        var i = contentRange.location
        let end = NSMaxRange(contentRange)
        while i < end, ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 {
            i += 1
        }
        guard i + 3 <= end,
              ns.character(at: i) == 0x5B,      // [
              ns.character(at: i + 1) == 0x21   // !
        else { return nil }
        let typeStart = i + 2
        var j = typeStart
        while j < end {
            let ch = ns.character(at: j)
            if ch == 0x5D { break }             // ]
            let isAlpha = (ch >= 0x41 && ch <= 0x5A) || (ch >= 0x61 && ch <= 0x7A)
            let isDigit = ch >= 0x30 && ch <= 0x39
            let isSep = ch == 0x2D || ch == 0x5F
            guard isAlpha || isDigit || isSep else { return nil }
            j += 1
        }
        guard j < end, ns.character(at: j) == 0x5D, j > typeStart else { return nil }
        let type = ns.substring(with: NSRange(location: typeStart, length: j - typeStart))
        return CalloutMarker(
            type: type,
            markerRange: NSRange(location: i, length: (j + 1) - i)
        )
    }

    public static func appearance(for rawType: String) -> CalloutAppearance {
        let key = rawType.lowercased()
        let family = family(for: key)
        return CalloutAppearance(
            type: rawType,
            label: label(for: key, family: family),
            symbolName: family.symbolName,
            accent: family.accent,
            background: family.background
        )
    }

    private static func label(for key: String, family: Family) -> String {
        if key.isEmpty { return family.label }
        return key.prefix(1).uppercased() + key.dropFirst()
    }

    private static func family(for key: String) -> Family {
        switch key {
        case "tip", "hint":
            return .init(label: "Tip", symbolName: "lightbulb.fill",
                         light: (0.10, 0.55, 0.55), dark: (0.45, 0.82, 0.82))
        case "warning", "caution", "attention":
            return .init(label: "Warning", symbolName: "exclamationmark.triangle.fill",
                         light: (0.78, 0.48, 0.08), dark: (0.98, 0.72, 0.28))
        case "error", "danger", "failure", "fail", "bug":
            return .init(label: "Error", symbolName: "xmark.octagon.fill",
                         light: (0.78, 0.18, 0.20), dark: (0.96, 0.48, 0.48))
        case "success", "check", "done":
            return .init(label: "Success", symbolName: "checkmark.circle.fill",
                         light: (0.18, 0.58, 0.32), dark: (0.48, 0.84, 0.58))
        case "question", "help", "faq":
            return .init(label: "Question", symbolName: "questionmark.circle.fill",
                         light: (0.72, 0.52, 0.08), dark: (0.96, 0.78, 0.32))
        case "important":
            return .init(label: "Important", symbolName: "star.fill",
                         light: (0.52, 0.28, 0.72), dark: (0.78, 0.58, 0.96))
        case "quote", "cite":
            return .init(label: "Quote", symbolName: "quote.opening",
                         light: (0.42, 0.44, 0.48), dark: (0.72, 0.74, 0.78))
        case "abstract", "summary", "tldr", "example":
            return .init(label: "Example", symbolName: "text.alignleft",
                         light: (0.38, 0.32, 0.72), dark: (0.68, 0.62, 0.96))
        case "todo":
            return .init(label: "Todo", symbolName: "circle",
                         light: (0.22, 0.40, 0.78), dark: (0.55, 0.68, 0.98))
        case "info":
            return .init(label: "Info", symbolName: "info.circle.fill",
                         light: (0.22, 0.40, 0.78), dark: (0.55, 0.68, 0.98))
        default:
            return .init(label: "Note", symbolName: "info.circle.fill",
                         light: (0.22, 0.40, 0.78), dark: (0.55, 0.68, 0.98))
        }
    }

    private struct Family {
        let label: String
        let symbolName: String
        let light: (CGFloat, CGFloat, CGFloat)
        let dark: (CGFloat, CGFloat, CGFloat)

        var accent: NSColor {
            NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let c = isDark ? dark : light
                return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
            }
        }

        var background: NSColor {
            NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let c = isDark ? dark : light
                // Full-column box fill; keep this quieter than a glyph-run highlight.
                return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: isDark ? 0.14 : 0.10)
            }
        }
    }

    static let titleIconGap: CGFloat = 6
    static let boxCornerRadius: CGFloat = 8
    static let boxHorizontalInset: CGFloat = 2
    static let boxVerticalPad: CGFloat = 5

    /// Width of the painted icon + label so the hidden `[!type]` run can kern to it.
    static func titleWidth(for appearance: CalloutAppearance, bodyPointSize: CGFloat) -> CGFloat {
        let titleFont = NSFont.systemFont(ofSize: bodyPointSize, weight: .semibold)
        let labelWidth = (appearance.label as NSString).size(withAttributes: [.font: titleFont]).width
        return bodyPointSize * 0.95 + titleIconGap + labelWidth
    }
}

public struct CalloutMarker: Equatable, Sendable {
    public var type: String
    public var markerRange: NSRange
}

public struct CalloutAppearance: Sendable {
    public var type: String
    public var label: String
    public var symbolName: String
    public var accent: NSColor
    public var background: NSColor
}
