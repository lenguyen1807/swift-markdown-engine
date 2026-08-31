//
//  CalloutExtensionTests.swift
//  MarkdownEngineTests
//
//  Opt-in `> [!type]` callouts: parse, restyle as a tinted titled box,
//  reveal source while the caret is inside, copy as a blockquote.
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine

@Suite("Callout extension")
struct CalloutExtensionTests {

    private var config: MarkdownEditorConfiguration {
        MarkdownEditorConfiguration(extensions: [CalloutExtension()])
    }

    private func attrs(
        _ text: String,
        caret: Int = -1,
        configuration: MarkdownEditorConfiguration? = nil
    ) -> [StyledRange] {
        MarkdownASTStyler.styleAttributes(
            text: text, fontName: "Helvetica", fontSize: 14, caretLocation: caret,
            configuration: configuration ?? config
        )
    }

    private func color(in styled: [StyledRange], at pos: Int) -> NSColor? {
        styled.last { NSLocationInRange(pos, $0.range) }.flatMap { $0.attributes[.foregroundColor] as? NSColor }
    }

    @Test("without the extension, [!note] is an ordinary blockquote")
    func unregisteredStaysBlockquote() {
        let text = "> [!note]\n> Body"
        let nodes = DocumentAST.parse(text)
        guard case .blockquote = nodes.first else {
            Issue.record("expected blockquote, got \(nodes)")
            return
        }
        let styled = attrs(text, configuration: .default)
        let markerPos = (text as NSString).range(of: "[!note]").location
        #expect(styled.contains { range, a in
            NSLocationInRange(markerPos, range) && a[.calloutTitle] != nil
        } == false)
    }

    @Test("a registered callout still parses as a blockquote")
    func stillABlockquote() {
        let text = "> [!warning]\n> Careful"
        let nodes = DocumentAST.parse(text, registry: ExtensionRegistry(extensions: [CalloutExtension()]))
        guard case .blockquote = nodes.first else {
            Issue.record("expected blockquote"); return
        }
    }

    @Test("parses [!type] at the start of dequoted content")
    func markerParse() {
        let ns = "[!tip]" as NSString
        let marker = CalloutExtension.marker(in: ns, contentRange: NSRange(location: 0, length: ns.length))
        #expect(marker?.type == "tip")
        #expect(marker?.markerRange == NSRange(location: 0, length: 6))
        #expect(CalloutExtension.marker(in: "not a callout" as NSString, contentRange: NSRange(location: 0, length: 13)) == nil)
    }

    @Test("unknown types still get a default appearance and keep their name")
    func unknownTypeFallsBack() {
        let appearance = CalloutExtension.appearance(for: "custom-kind")
        #expect(appearance.label == "Custom-kind")
        #expect(appearance.symbolName == "info.circle.fill")
    }

    @Test("inactive callout hides [!type] and paints a title + background")
    func inactiveHidesMarker() {
        let text = "> [!note]\n> Body"
        let styled = attrs(text, caret: -1)
        let markerPos = (text as NSString).range(of: "[!note]").location
        #expect(styled.contains { range, a in
            NSLocationInRange(markerPos, range) && (a[.calloutTitle] as? String) == "note"
        })
        #expect(color(in: styled, at: markerPos) == NSColor.clear)
        let bodyPos = (text as NSString).range(of: "Body").location
        #expect(styled.contains { range, a in
            NSLocationInRange(bodyPos, range) && (a[.calloutType] as? String) == "note"
        })
        #expect(styled.contains { range, a in
            NSLocationInRange(bodyPos, range) && a[.markdownBlockBackground] != nil
        } == false)
    }

    @Test("caret inside a callout reveals the source markers")
    func activeRevealsMarkers() {
        let text = "> [!note]\n> Body"
        let styled = attrs(text, caret: 4)
        let markerPos = (text as NSString).range(of: "[!note]").location
        #expect(styled.contains { range, a in
            NSLocationInRange(markerPos, range) && a[.calloutTitle] != nil
        } == false)
        #expect(color(in: styled, at: markerPos) == MarkdownEditorTheme.default.mutedText)
    }

    @Test("HTML copy emits a blockquote")
    func htmlIsBlockquote() {
        let md = "> [!tip]\n> Hello **there**"
        let html = MarkdownHTMLRenderer.html(from: md, extensions: [CalloutExtension()])
        #expect(html.contains("<blockquote>"))
        #expect(html.contains("<strong>there</strong>"))
    }

    @Test("inactive title run kerns to the painted icon+label width")
    func inactiveTitleReservesWidth() {
        let text = "> [!note]\n> Body"
        let styled = attrs(text, caret: -1)
        let marker = (text as NSString).range(of: "[!note]")
        let titleRun = styled.last { range, a in
            NSLocationInRange(marker.location, range) && a[.calloutTitle] != nil
        }
        #expect(titleRun?.attributes[.kern] as? CGFloat != nil)
    }
}
