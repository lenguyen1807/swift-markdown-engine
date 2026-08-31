//
//  CalloutBoxFillTests.swift
//  MarkdownEngineTests
//
//  Callout boxes fill the COLUMN, not the glyph run: a titled box has to read
//  as one rounded rectangle rather than highlighter strips behind each line.
//

import AppKit
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("Callout box fills")
struct CalloutBoxFillTests {

    private func makeTextView(
        _ text: String,
        width: CGFloat = 320,
        fontSize: CGFloat = 16
    ) -> NativeTextView {
        let tv = NativeTextView(frame: NSRect(x: 0, y: 0, width: width, height: 400))
        var config = MarkdownEditorConfiguration.default
        config.extensions = [CalloutExtension()]
        tv.configuration = config
        let (font, style) = TextStylingService.makeBaseFontAndStyle(
            fontName: NSFont.systemFont(ofSize: fontSize).fontName,
            fontSize: fontSize,
            layoutBridge: tv.layoutBridge,
            configuration: config
        )
        tv.baseFont = font
        tv.textContainer?.size = NSSize(width: width, height: .greatestFiniteMagnitude)
        tv.textStorage?.setAttributedString(NSAttributedString(
            string: text,
            attributes: [.font: font, .paragraphStyle: style]
        ))
        return tv
    }

    private func fills(in tv: NativeTextView) -> [MarkdownTextLayoutFragment.CalloutBoxFill] {
        guard let tlm = tv.textLayoutManager, let tcm = tlm.textContentManager else { return [] }
        let delegate = MarkdownLayoutManagerDelegate()
        tlm.delegate = delegate
        tlm.invalidateLayout(for: tlm.documentRange)
        tlm.ensureLayout(for: tlm.documentRange)

        var result: [MarkdownTextLayoutFragment.CalloutBoxFill] = []
        tlm.enumerateTextLayoutFragments(from: tcm.documentRange.location, options: [.ensuresLayout]) { fragment in
            guard let fragment = fragment as? MarkdownTextLayoutFragment else { return true }
            let origin = fragment.layoutFragmentFrame.origin
            result += fragment.calloutBoxFills(at: origin)
            return true
        }
        return result
    }

    @Test("a callout fills the container width, not the glyph run")
    func fillsContainerWidth() {
        let text = "short"
        let width: CGFloat = 320
        let tv = makeTextView(text, width: width)
        tv.textStorage?.addAttribute(
            .calloutType, value: "warning",
            range: NSRange(location: 0, length: (text as NSString).length)
        )
        let boxes = fills(in: tv)
        #expect(boxes.count == 1)
        let box = boxes[0].rect
        #expect(box.width > width - 8, "box \(box.width) should span the \(width)pt column")
        let glyphWidth = (text as NSString).size(withAttributes: [.font: tv.baseFont]).width
        #expect(box.width > glyphWidth + 40, "box must be wider than the glyphs (\(glyphWidth))")
        #expect(boxes[0].roundTop && boxes[0].roundBottom)
    }

    @Test("wrapped callout lines meet as one box")
    func wrappedLinesMeet() {
        let text = "one two three four five six seven eight nine ten eleven twelve"
        let tv = makeTextView(text, width: 160)
        tv.textStorage?.addAttribute(
            .calloutType, value: "note",
            range: NSRange(location: 0, length: (text as NSString).length)
        )
        let boxes = fills(in: tv)
        #expect(boxes.count >= 3, "sample must wrap, got \(boxes.count)")
        #expect(boxes.first?.roundTop == true)
        #expect(boxes.last?.roundBottom == true)
        #expect(boxes.dropFirst().dropLast().allSatisfy { !$0.roundTop && !$0.roundBottom })
        for (upper, lower) in zip(boxes, boxes.dropFirst()) {
            #expect(abs(lower.rect.minY - upper.rect.maxY) < 0.5, "seam between \(upper.rect) and \(lower.rect)")
        }
    }

    @Test("plain text does not paint a callout box")
    func plainTextDoesNotFill() {
        let tv = makeTextView("plain text", width: 400)
        #expect(fills(in: tv).isEmpty)
    }
}
