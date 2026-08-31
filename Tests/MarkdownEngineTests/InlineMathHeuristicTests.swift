//
//  InlineMathHeuristicTests.swift
//  MarkdownEngineTests
//
//  `$Z[i,j]$` and `$O(BFD)$` are math, not prose with leftover dollars.
//

import Foundation
import Testing
@testable import MarkdownEngine

@Suite("Inline math heuristic")
struct InlineMathHeuristicTests {

    private func latexContents(_ text: String) -> [String] {
        let ns = text as NSString
        let nodes = DocumentAST.parse(text)
        var out: [String] = []
        func walk(_ nodes: [InlineNode]) {
            for node in nodes {
                switch node {
                case .inlineLatex(_, let content, _):
                    out.append(ns.substring(with: content))
                case .emphasis(_, _, _, let children), .link(_, _, _, _, let children):
                    walk(children)
                case .ext(let node):
                    walk(node.children)
                default:
                    break
                }
            }
        }
        for block in nodes {
            if case .paragraph(_, let inlines) = block { walk(inlines) }
        }
        return out
    }

    @Test("matrix indices and big-O calls parse as inline math")
    func indexingAndCallsParse() {
        let contents = latexContents("Cost is $O(BFD)$ and $Z[i,j]$.")
        #expect(contents.contains("O(BFD)"))
        #expect(contents.contains("Z[i,j]"))
    }

    @Test("currency-like dollars stay prose")
    func currencyStaysProse() {
        #expect(latexContents("It costs $50.").isEmpty)
    }
}
