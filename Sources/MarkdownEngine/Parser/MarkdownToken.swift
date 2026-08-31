//
//  MarkdownToken.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 18.02.26.
//

// Defines the basic Markdown building blocks the editor works with (bold,
// links, code, LaTeX, etc.), plus shared text attributes.
import AppKit
import Foundation

extension NSAttributedString.Key {
    public static let wikiLinkID = NSAttributedString.Key("NodeLinkID")
    public static let taskCheckbox = NSAttributedString.Key("TaskCheckbox")
}

enum MarkdownTokenKind: Equatable {
    case italic
    case boldItalic
    case bold
    case link
    case wikiLink
    case heading
    /// One blockquote line; `markerRanges[0]` is the `>` run, nesting = count of `>`.
    case blockquote
    case codeBlock
    case inlineCode
    case blockLatex
    case inlineLatex
    case imageEmbed
    case imageLink
    case table
    /// A CommonMark backslash escape; marker is the `\`, content the escaped literal char.
    case backslashEscape
    /// A span contributed by a registered `MarkdownExtension`,
    /// carrying the extension's id (e.g. `.extensionSpan("highlight")`).
    case extensionSpan(String)
    /// A fenced block contributed by a registered `MarkdownExtension`,
    /// carrying the extension's id (e.g. `.extensionBlock("container")`).
    case extensionBlock(String)
}

struct MarkdownToken {
    let kind: MarkdownTokenKind
    let range: NSRange
    let contentRange: NSRange
    let markerRanges: [NSRange]
}

extension MarkdownToken {
    func standaloneParagraphRange(in text: NSString) -> NSRange? {
        let paragraphRange = text.paragraphRange(for: range)
        let paragraphText = text.substring(with: paragraphRange) as NSString
        let tokenRelativeRange = NSRange(
            location: range.location - paragraphRange.location,
            length: range.length
        )
        let mutableParagraph = paragraphText.mutableCopy() as! NSMutableString
        mutableParagraph.replaceCharacters(in: tokenRelativeRange, with: "")
        let leftover = mutableParagraph as String
        if leftover.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return paragraphRange }
        // Quoted display math: stripping `$$…$$` leaves the `>` prefixes.
        return Self.isOnlyBlockquotePrefixes(leftover) ? paragraphRange : nil
    }

    /// True when every line is blank or a blockquote marker with no other content.
    private static func isOnlyBlockquotePrefixes(_ text: String) -> Bool {
        let ns = text as NSString
        var lineStart = 0
        let len = ns.length
        while lineStart < len {
            var lineEnd = lineStart
            while lineEnd < len {
                let ch = ns.character(at: lineEnd)
                if ch == 0x0A || ch == 0x0D { break }
                lineEnd += 1
            }
            var i = lineStart
            var indent = 0
            while i < lineEnd, indent < 3 {
                let ch = ns.character(at: i)
                guard ch == 0x20 || ch == 0x09 else { break }
                i += 1; indent += 1
            }
            while i < lineEnd, ns.character(at: i) == 0x3E {
                i += 1
                if i < lineEnd {
                    let ch = ns.character(at: i)
                    if ch == 0x20 || ch == 0x09 { i += 1 }
                }
            }
            while i < lineEnd {
                let ch = ns.character(at: i)
                if ch != 0x20 && ch != 0x09 { return false }
                i += 1
            }
            lineStart = lineEnd
            if lineStart < len, ns.character(at: lineStart) == 0x0D { lineStart += 1 }
            if lineStart < len, ns.character(at: lineStart) == 0x0A { lineStart += 1 }
        }
        return true
    }

    func containsSelectionOrStandaloneParagraph(_ selectionLocation: Int, in text: NSString) -> Bool {
        let start = range.location
        let end = NSMaxRange(range) - 1
        if selectionLocation >= start && selectionLocation <= end {
            return true
        }

        guard let paragraphRange = standaloneParagraphRange(in: text) else {
            return false
        }
        let paragraphEnd = NSMaxRange(paragraphRange)
        // Reveal source when caret is at document end right after the image, unless that line ends in a newline.
        let endsWithNewline = paragraphEnd > paragraphRange.location
            && (text.character(at: paragraphEnd - 1) == 0x0A || text.character(at: paragraphEnd - 1) == 0x0D)
        let isAtLastParagraphEnd = selectionLocation == text.length
            && paragraphEnd == text.length && !endsWithNewline
        return (selectionLocation >= paragraphRange.location && selectionLocation < paragraphEnd)
            || isAtLastParagraphEnd
    }
}
