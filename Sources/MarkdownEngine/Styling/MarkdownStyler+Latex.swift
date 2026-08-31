//
//  MarkdownStyler+Latex.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 16.03.26.
//
//  Block ($$...$$) and inline ($...$) LaTeX formula rendering.
//

import AppKit
import Foundation

extension MarkdownStyler {

    // MARK: Block LaTeX $$...$$

    static func styleBlockLatex(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        for (idx, token) in ctx.scoped(ctx.blockLatexIndexed) {
            if MarkdownDetection.isInsideCodeBlock(range: token.range, codeTokens: ctx.codeTokens) { continue }
            let isActive = ctx.activeTokenIndices.contains(idx)
            let rawLatexContent = ctx.nsText.substring(with: token.contentRange)

            attrs.append((token.range, [NSAttributedString.Key.spellingState: 0]))

            guard token.standaloneParagraphRange(in: ctx.nsText) != nil else { continue }

            let latexFontSize = HeadingHelpers.latexFontSize(for: token, headings: [], baseFont: ctx.baseFont)  // block $$ is never inside a heading
            let renderSource = dequoteBlockquotePrefixes(rawLatexContent)

            if isActive {
                appendSecondaryMarkers(for: token, to: &attrs, theme: ctx.configuration.theme)
            } else if !renderSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let entry = ctx.services.latex.render(latex: renderSource, fontSize: latexFontSize, theme: ctx.configuration.theme) {
                _ = appendRenderedStandaloneBlock(
                    for: token,
                    rawContent: rawLatexContent,
                    image: entry.image,
                    imageBounds: CGRect(
                        x: 0,
                        y: entry.baselineOffset,
                        width: entry.size.width,
                        height: entry.size.height
                    ),
                    paragraphSpacingBefore: ctx.configuration.blockLatex.paragraphSpacingBefore,
                    paragraphSpacing: ctx.configuration.blockLatex.paragraphSpacing,
                    alignment: .center,
                    mode: .collapsedSource(markerTexts: ["$$", "$$"]),
                    ctx: ctx,
                    attrs: &attrs
                )
            } else {
                appendSecondaryMarkers(for: token, to: &attrs, theme: ctx.configuration.theme)
            }
        }
        return attrs
    }

    // MARK: Inline LaTeX $formula$

    static func styleInlineLatex(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        // Tables render their own cell contents (including `$…$`) into a single
        // image via `formattedCellString` + `collapsedSource`. If we also tag
        // the source-text `$x^2$` with a `.latexImage` attribute, the renderer
        // draws that tiny inline image on the collapsed 1pt source line under
        // the table — visible as a stray dot. Skip inline LaTeX inside a
        // table; the table image already covers it.
        let scopedLatex = ctx.scoped(ctx.inlineLatexIndexed)
        guard !scopedLatex.isEmpty else { return attrs }
        // Containers that ENCLOSE an in-scope formula must overlap the scope, so
        // scope-slicing these is exact; built once, not per formula.
        let tableRanges = ctx.scoped(ctx.tableIndexed).map { $0.token.range }
        // Quote lines mute their text via foregroundColor, which the LaTeX *image* ignores — render it in mutedText instead so it matches the grey.
        // Callout bodies use body text, so keep the theme's latex colors there.
        let blockquoteRanges = MarkdownStyler.StylingContext.indexed(ctx.tokens, .blockquote).map { $0.token.range }
        let calloutQuoteRanges = calloutEnclosingRanges(blockquoteRanges: blockquoteRanges, ns: ctx.nsText, extensions: ctx.configuration.extensionsByID)
        // Built once, not re-scanned per formula (latexFontSize was O(#latex × #tokens)).
        let headings = ctx.scoped(MarkdownStyler.StylingContext.indexed(ctx.tokens, .heading)).map { $0.token }
        // Each textWidth is a CoreText measurement; the two "$" marker widths are
        // loop-invariant (fonts constant) and firstChar/restText repeat massively (2
        // distinct formulas × 1,594 tokens). Hoisting + memoizing removes all per-formula
        // width measurement — ENG-8g2b self ~186ms→~152ms on the 346k note (Debug).
        let tinyDollarWidth = HeadingHelpers.textWidth("$", font: ctx.latexMarkerFont)
        let baseDollarWidth = HeadingHelpers.textWidth("$", font: ctx.baseFont)
        var markerFontWidthCache: [String: CGFloat] = [:]  // all measured with latexMarkerFont
        func markerFontWidth(_ s: String) -> CGFloat {
            if let cached = markerFontWidthCache[s] { return cached }
            let w = HeadingHelpers.textWidth(s, font: ctx.latexMarkerFont)
            markerFontWidthCache[s] = w
            return w
        }
        for (idx, token) in scopedLatex {
            if MarkdownDetection.isInsideCodeBlock(range: token.range, codeTokens: ctx.codeTokens) { continue }
            if tableRanges.contains(where: { tableRange in
                token.range.location >= tableRange.location
                    && NSMaxRange(token.range) <= NSMaxRange(tableRange)
            }) { continue }

            attrs.append((token.range, [NSAttributedString.Key.spellingState: 0]))

            let isActive = ctx.activeTokenIndices.contains(idx)
            let latexContent = ctx.nsText.substring(with: token.contentRange)
            let latexFontSize = HeadingHelpers.latexFontSize(for: token, headings: headings, baseFont: ctx.baseFont)

            if isActive {
                for markerRange in token.markerRanges {
                    attrs.append((markerRange, [.foregroundColor: ctx.configuration.theme.mutedText]))
                }
            } else {
                var renderTheme = ctx.configuration.theme
                if blockquoteRanges.contains(where: { NSLocationInRange(token.range.location, $0) }),
                   !calloutQuoteRanges.contains(where: { NSLocationInRange(token.range.location, $0) }) {
                    renderTheme.latexLightModeText = renderTheme.mutedText
                    renderTheme.latexDarkModeText = renderTheme.mutedText
                }
                if let entry = ctx.services.latex.render(latex: latexContent, fontSize: latexFontSize, theme: renderTheme) {
                    let imageBounds = CGRect(x: 0, y: entry.baselineOffset, width: entry.size.width, height: entry.size.height)
                    let contentLength = token.contentRange.length

                    if contentLength > 0 {
                        let firstCharRange = NSRange(location: token.contentRange.location, length: 1)
                        let firstChar = ctx.nsText.substring(with: firstCharRange)
                        attrs.append((firstCharRange, [
                            .latexImage: entry.image,
                            .latexBounds: NSValue(rect: imageBounds),
                            .foregroundColor: NSColor.clear,
                            .font: ctx.latexMarkerFont,
                            .kern: entry.size.width - markerFontWidth(firstChar)
                        ]))

                        if contentLength > 1 {
                            let restRange = NSRange(location: token.contentRange.location + 1, length: contentLength - 1)
                            let restText = ctx.nsText.substring(with: restRange)
                            attrs.append((restRange, [
                                .foregroundColor: NSColor.clear,
                                .font: ctx.latexMarkerFont,
                                .kern: -markerFontWidth(restText)
                            ]))
                        }
                    }

                    let openMarker = token.markerRanges[0]
                    attrs.append((openMarker, [
                        .font: ctx.latexMarkerFont,
                        .foregroundColor: NSColor.clear,
                        .kern: -tinyDollarWidth
                    ]))
                    let closeMarker = token.markerRanges[1]
                    attrs.append((closeMarker, [
                        .foregroundColor: NSColor.clear,
                        .kern: -baseDollarWidth
                    ]))
                } else {
                    for markerRange in token.markerRanges {
                        attrs.append((markerRange, [.foregroundColor: ctx.configuration.theme.mutedText]))
                    }
                }
            }
        }
        return attrs
    }

    /// Strip `>` quote prefixes from each line so nested `$$` in a callout
    /// typesets as math instead of `> \max(...)`.
    static func dequoteBlockquotePrefixes(_ raw: String) -> String {
        let ns = raw as NSString
        var lineStart = 0
        let len = ns.length
        var lines: [String] = []
        while lineStart <= len {
            if lineStart == len {
                if raw.hasSuffix("\n") { lines.append("") }
                break
            }
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
            lines.append(ns.substring(with: NSRange(location: i, length: lineEnd - i)))
            lineStart = lineEnd
            if lineStart < len, ns.character(at: lineStart) == 0x0D { lineStart += 1 }
            if lineStart < len, ns.character(at: lineStart) == 0x0A { lineStart += 1 }
            if lineStart >= len { break }
        }
        return lines.joined(separator: "\n")
    }

    /// Consecutive quote-line ranges that belong to a `> [!type]` callout.
    private static func calloutEnclosingRanges(
        blockquoteRanges: [NSRange],
        ns: NSString,
        extensions: [String: any MarkdownExtension]
    ) -> [NSRange] {
        guard extensions[CalloutExtension.identifier] != nil, !blockquoteRanges.isEmpty else { return [] }
        let ordered = blockquoteRanges.sorted { $0.location < $1.location }
        var result: [NSRange] = []
        var run: [NSRange] = []
        func flush() {
            guard let first = run.first else { return }
            if CalloutExtension.marker(in: ns, contentRange: dequotedLineContent(first, ns: ns)) != nil {
                result.append(contentsOf: run)
            }
            run.removeAll(keepingCapacity: true)
        }
        for range in ordered {
            if let last = run.last, NSMaxRange(last) >= range.location - 2 {
                run.append(range)
            } else {
                flush()
                run = [range]
            }
        }
        flush()
        return result
    }

    private static func dequotedLineContent(_ range: NSRange, ns: NSString) -> NSRange {
        var i = range.location
        let end = NSMaxRange(range)
        var indent = 0
        while i < end, indent < 3 {
            let ch = ns.character(at: i)
            guard ch == 0x20 || ch == 0x09 else { break }
            i += 1; indent += 1
        }
        while i < end, ns.character(at: i) == 0x3E {
            i += 1
            if i < end {
                let ch = ns.character(at: i)
                if ch == 0x20 || ch == 0x09 { i += 1 }
            }
        }
        return NSRange(location: i, length: max(0, end - i))
    }
}
