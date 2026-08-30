//
//  NativeTextView+TableWikiLinks.swift
//  MarkdownEngine
//
//  Clicking a `[[wiki-link]]` inside a rendered table image navigates instead
//  of entering table source-edit mode. Hits are recorded in image coordinates
//  at render time and stored on the collapsed-source anchor.
//

import AppKit

extension NativeTextView {

    /// Navigate if the click lands on a wiki-link inside a collapsed table image.
    /// Returns true when the click was consumed.
    func navigateTableWikiLinkIfHit(event: NSEvent) -> Bool {
        guard let identifier = tableWikiLinkIdentifier(at: event) else { return false }
        guard let coord = delegate as? NativeTextViewCoordinator else { return false }
        linkClickDidFire = true
        linkClickDidNavigate = true
        coord.isWikiLinkActive = false
        DispatchQueue.main.async {
            coord.onLinkClick?(identifier)
        }
        return true
    }

    func tableWikiLinkIdentifier(at event: NSEvent) -> String? {
        guard let storage = textStorage, storage.length > 0,
              let bridge = layoutBridge,
              let textContainer else { return nil }
        let localPoint = convert(event.locationInWindow, from: nil)
        let idx = characterIndexForInsertion(at: localPoint)
        guard idx >= 0, idx < storage.length,
              let hits = storage.attribute(.tableWikiLinkHits, at: idx, effectiveRange: nil) as? TableWikiLinkHitMap
        else { return nil }
        let containerPoint = CGPoint(
            x: localPoint.x - textContainerOrigin.x,
            y: localPoint.y - textContainerOrigin.y
        )
        let anchor = bridge.boundingRect(
            forCharacterRange: NSRange(location: idx, length: 1),
            in: textContainer
        )
        guard !anchor.isEmpty else { return nil }
        let imagePoint = CGPoint(x: containerPoint.x - anchor.minX, y: containerPoint.y - anchor.minY)
        return hits.identifier(at: imagePoint)
    }
}
