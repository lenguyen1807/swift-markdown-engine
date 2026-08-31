//
//  CalloutLatexTests.swift
//  MarkdownEngineTests
//
//  Display math inside `> [!type]` (quoted and lazy-continued) must tokenize
//  as block LaTeX so it can render as an image instead of raw source.
//

import Foundation
import Testing
@testable import MarkdownEngine

@Suite("Callout display math")
struct CalloutLatexTests {

    private let registry = ExtensionRegistry(extensions: [CalloutExtension()])

    @Test("quoted $$ inside a callout is a block-latex token")
    func quotedDisplayMathTokenizes() {
        let text = "> [!warning]\n> $$\n> x^2\n> $$\n"
        let tokens = MarkdownTokenizer.parseTokensViaAST(in: text, registry: registry)
        #expect(tokens.contains { $0.kind == .blockLatex })
        let latex = tokens.first { $0.kind == .blockLatex }
        let content = (text as NSString).substring(with: latex!.contentRange)
        #expect(MarkdownStyler.dequoteBlockquotePrefixes(content).contains("x^2"))
        #expect(latex?.standaloneParagraphRange(in: text as NSString) != nil)
    }

    @Test("unquoted formula lines between > $$ stay in the callout")
    func lazyContinuationKeepsFormulaInQuote() {
        let text = "> [!note]\n> $$\n\\frac{1}{2}\n> $$\n"
        let blocks = BlockParser.parse(text, registry: registry)
        #expect(blocks.filter { $0.kind == .blockquote }.count == 1)
        #expect(blocks.contains { $0.kind == .blockLatex } == false)
        let tokens = MarkdownTokenizer.parseTokensViaAST(in: text, registry: registry)
        #expect(tokens.contains { $0.kind == .blockLatex })
    }

    @Test("unquoted $$ after a blank line is its own block")
    func outsideDisplayMathStaysABlock() {
        let text = "Hello\n\n$$\nx^2\n$$\n"
        let blocks = BlockParser.parse(text)
        #expect(blocks.contains { $0.kind == .blockLatex })
        let tokens = MarkdownTokenizer.parseTokensViaAST(in: text)
        #expect(tokens.contains { $0.kind == .blockLatex })
        let latex = tokens.first { $0.kind == .blockLatex }!
        #expect(latex.standaloneParagraphRange(in: text as NSString) != nil)
    }

    @Test("fold + after [!type] is not the type name")
    func foldPlusIsNotTheType() {
        let ns = "[!Important]+ Time communication" as NSString
        let marker = CalloutExtension.marker(in: ns, contentRange: NSRange(location: 0, length: ns.length))
        #expect(marker?.type == "Important")
        #expect(ns.substring(with: marker!.markerRange) == "[!Important]+")
    }

    @Test("dequote strips nested quote markers from latex")
    func dequoteStripsGt() {
        let raw = "\n> \\max(a,b)\n> "
        #expect(MarkdownStyler.dequoteBlockquotePrefixes(raw).contains("\\max(a,b)"))
        #expect(MarkdownStyler.dequoteBlockquotePrefixes(raw).contains(">") == false)
    }
}
