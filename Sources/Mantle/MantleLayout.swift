import SwiftUI

/// Resolved geometry for one layout pass: where every detent rests and how the
/// surface looks at any top-edge position in between.
struct MantleLayout {
    struct Entry {
        let detent: MantleDetent
        /// Empty for snap-point-only detents.
        var content: [Subview]
        var top: CGFloat = 0
        /// Where a downward drag from this detent goes; see `MantleCollapseMode`.
        var collapseMode: MantleCollapseMode = .automatic
    }

    let size: CGSize
    let safeArea: EdgeInsets
    let collapsed: MantleCollapsedLayout
    let cornerRadius: CGFloat
    /// Distance from the bottom of the screen to the bottom of the collapsed bar.
    let collapsedBottomGap: CGFloat
    /// Sorted from the resting (lowest) detent to the largest.
    let entries: [Entry]

    init(
        size: CGSize,
        safeArea: EdgeInsets,
        tabBarTop: CGFloat?,
        collapsed: MantleCollapsedLayout,
        cornerRadius: CGFloat,
        entries: [Entry],
        expandedContent: [Subview],
        revealMarkers: [MantleRevealMarker]
    ) {
        let expandedCollapseMode = expandedContent.lazy.map(\.containerValues.mantleCollapseMode).first { $0 != .automatic } ?? .automatic
        self.size = size
        self.safeArea = safeArea
        self.collapsed = collapsed
        self.cornerRadius = cornerRadius

        let bottomGap = if let tabBarTop, tabBarTop < size.height {
            size.height - tabBarTop + collapsed.bottomInset
        } else {
            safeArea.bottom + collapsed.bottomInset
        }
        self.collapsedBottomGap = bottomGap
        let collapsedTop = size.height - bottomGap - collapsed.height
        let largeTop = safeArea.top

        func top(_ detent: MantleDetent) -> CGFloat {
            switch detent.storage {
            case .collapsed: collapsedTop
            case .fraction(let f): max(largeTop, size.height * (1 - f))
            case .height(let h): max(largeTop, size.height - safeArea.bottom - h)
            case .large, .reveal: largeTop
            case .fullScreen: 0
            }
        }

        var sorted = entries
            .map { var e = $0; e.top = top(e.detent); return e }
            .sorted { $0.top > $1.top }

        // Unmarked views are the expanded content. They live at `.large`, or at a
        // declared content-less detent at least that tall (e.g. `.fullScreen`);
        // otherwise an implicit `.large` is added. Smaller declared detents stay
        // snap points that reveal it.
        var expandedTop: CGFloat?
        if !expandedContent.isEmpty {
            if let index = sorted.lastIndex(where: { !$0.detent.isCollapsed && $0.top <= largeTop }) {
                if sorted[index].content.isEmpty {
                    sorted[index].content = expandedContent
                    if sorted[index].collapseMode == .automatic { sorted[index].collapseMode = expandedCollapseMode }
                    expandedTop = sorted[index].top
                }
            } else {
                sorted.append(Entry(detent: .large, content: expandedContent, top: largeTop, collapseMode: expandedCollapseMode))
                expandedTop = largeTop
            }
        }

        // Reveal markers add snap points showing the expanded content down to each one.
        if let expandedTop, let restTop = sorted.first?.top {
            var unnamed = 0
            for marker in revealMarkers.sorted(by: { $0.maxY < $1.maxY }) {
                let detent: MantleDetent = if let name = marker.name {
                    .revealed(name)
                } else {
                    .revealed(unnamed)
                }
                if marker.name == nil { unnamed += 1 }

                let markerTop = size.height - safeArea.bottom - marker.maxY
                guard markerTop > expandedTop + 1, markerTop < restTop - 1,
                      !sorted.contains(where: { $0.detent == detent || abs($0.top - markerTop) < 1 })
                else { continue }
                sorted.append(Entry(detent: detent, content: [], top: markerTop, collapseMode: marker.collapseMode))
            }
            sorted.sort { $0.top > $1.top }
        }

        // Snap points without content show another detent's content; dismissing
        // them should behave like dismissing that content, so they inherit its
        // collapse mode unless they set their own.
        for index in sorted.indices where sorted[index].content.isEmpty && sorted[index].collapseMode == .automatic {
            let owner = sorted[index...].first { !$0.content.isEmpty }
                ?? sorted[..<index].last { !$0.content.isEmpty }
            sorted[index].collapseMode = owner?.collapseMode ?? .automatic
        }

        self.entries = sorted
    }

    var hasCollapsed: Bool { entries.first?.detent.isCollapsed == true }
    var restTop: CGFloat { entries.first!.top }
    var largestTop: CGFloat { entries.last!.top }

    /// Entries that draw content, smallest first.
    var contentEntries: [Entry] { entries.filter { !$0.content.isEmpty } }

    /// Where a drag that started at `start` and would settle on `proposed` goes:
    /// the start detent's collapse target (`.target`), if the drag went down and the target is
    /// smaller than where it started.
    func settle(from start: MantleDetent, proposed: Entry) -> Entry {
        guard let startEntry = entries.first(where: { $0.detent == start }),
              proposed.top > startEntry.top + 1,
              case .target(let target) = startEntry.collapseMode,
              let targetEntry = entries.first(where: { $0.detent == target }),
              targetEntry.top > startEntry.top + 1
        else { return proposed }
        return targetEntry
    }

    func top(for detent: MantleDetent) -> CGFloat {
        entries.first { $0.detent == detent }?.top ?? restTop
    }

    /// Falls back to the resting detent for detents that don't exist (yet).
    func resolve(_ detent: MantleDetent) -> MantleDetent {
        entries.contains { $0.detent == detent } ? detent : entries.first!.detent
    }

    /// The entry whose content is shown at `detent`: itself, or for a snap point,
    /// the next larger detent with content (falling back to the next smaller one).
    private func owner(of detent: MantleDetent) -> Entry? {
        guard let index = entries.firstIndex(where: { $0.detent == detent }) else { return nil }
        return entries[index...].first { !$0.content.isEmpty }
            ?? entries[..<index].last { !$0.content.isEmpty }
    }

    /// The next resting position above `entry`, with or without content.
    private func entry(above entry: Entry) -> Entry? {
        entries.first { $0.top < entry.top }
    }

    func rubberBanded(_ top: CGFloat) -> CGFloat {
        func band(_ overshoot: CGFloat) -> CGFloat {
            let limit: CGFloat = 80
            return (1 - 1 / (overshoot * 0.55 / limit + 1)) * limit
        }
        if top < largestTop { return largestTop - band(largestTop - top) }
        if top > restTop { return restTop + band(top - restTop) }
        return top
    }

    /// 0 while collapsed, 1 once the surface has become an edge-to-edge sheet.
    func expansion(top: CGFloat) -> CGFloat {
        guard hasCollapsed else { return 1 }
        guard entries.count > 1 else { return 0 }
        let from = entries[0].top, to = entries[1].top
        return ((from - top) / (from - to)).clamped
    }

    /// How the surface is placed for a given top edge: a laid-out `frame`, plus a
    /// vertical `offset` applied as a render-time transform.
    ///
    /// While the collapsed bar morphs into the sheet, the frame itself changes
    /// (width, height, corner radius). Once it's a full sheet, the frame is fixed
    /// at full height (running off the bottom of the screen) and only the offset
    /// changes. Like a UIKit sheet, it slides instead of resizing, so dragging
    /// needs no layout and the background (notably Liquid Glass) isn't
    /// re-rendered at a new size every frame. The two agree on screen where they
    /// meet; they differ only below the bottom edge.
    func placement(top: CGFloat) -> (frame: CGRect, offset: CGFloat) {
        let sheetTop = hasCollapsed && entries.count > 1 ? entries[1].top : restTop
        let morphing = hasCollapsed && (entries.count == 1 || top > sheetTop)
        guard !morphing else { return (frame(top: top), 0) }
        // Tall enough to stay off the bottom of the screen while rubber-banding
        // above the largest detent.
        let anchor = largestTop
        let frame = CGRect(x: 0, y: anchor, width: size.width, height: size.height - anchor + Self.overscroll)
        return (frame, top - anchor)
    }

    /// Extra sheet height below the screen, covering upward rubber-banding.
    private static let overscroll: CGFloat = 120

    func frame(top: CGFloat) -> CGRect {
        let p = expansion(top: top)
        let inset = collapsed.horizontalInset * (1 - p)
        let bottomGap = hasCollapsed ? collapsedBottomGap * (1 - p) : 0
        var height = size.height - bottomGap - top
        if hasCollapsed, top > restTop {
            // Pulled down past the bar: slide it, don't squash it.
            height = collapsed.height
        }
        return CGRect(x: inset, y: top, width: size.width - inset * 2, height: max(height, 0))
    }

    func contentSize(for entry: Entry) -> CGSize {
        if entry.detent.isCollapsed {
            CGSize(width: size.width - collapsed.horizontalInset * 2, height: collapsed.height)
        } else {
            CGSize(width: size.width, height: size.height - entry.top)
        }
    }

    /// Keeps detent content out of the status bar / Dynamic Island and home indicator.
    func contentInsets(for entry: Entry, frameTop: CGFloat) -> EdgeInsets {
        guard !entry.detent.isCollapsed else { return EdgeInsets() }
        // Driven by where the sheet actually is, so content only gets pushed below
        // the status bar as a full-screen sheet reaches it.
        return EdgeInsets(
            top: max(0, safeArea.top - max(entry.top, frameTop)),
            leading: safeArea.leading,
            bottom: safeArea.bottom,
            trailing: safeArea.trailing
        )
    }

    /// Below the Dynamic Island if a full-screen sheet reaches the top of the screen.
    func grabberTop(frameTop: CGFloat) -> CGFloat {
        max(5, safeArea.top - 10 - frameTop)
    }

    func cornerRadius(top: CGFloat) -> CGFloat {
        let p = expansion(top: top)
        return collapsed.height / 2 * (1 - p) + cornerRadius * p
    }

    /// Cross-fade weights for each content entry at `top`.
    ///
    /// Content hands over to the next content-bearing detent while the sheet
    /// travels to the next resting position (content or not), so snap points
    /// between them show the incoming content fully, progressively revealed.
    func opacities(top: CGFloat, among detents: Set<MantleDetent>?) -> [MantleDetent: Double] {
        var anchors = contentEntries
        if let detents {
            let owners = Set(detents.compactMap { owner(of: $0)?.detent })
            anchors = anchors.filter { owners.contains($0.detent) }
        }
        var result: [MantleDetent: Double] = [:]
        guard let first = anchors.first, let last = anchors.last else { return result }
        if top >= first.top { result[first.detent] = 1; return result }
        if top <= last.top { result[last.detent] = 1; return result }
        for (lower, upper) in zip(anchors, anchors.dropFirst()) where top <= lower.top && top > upper.top {
            let end = entry(above: lower)?.top ?? upper.top
            let t = ((lower.top - top) / max(lower.top - end, 1)).clamped
            result[lower.detent] = 1 - smoothstep(0, 0.6, t)
            result[upper.detent] = smoothstep(0.35, 1, t)
        }
        return result
    }
}

private func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> Double {
    let t = ((x - edge0) / (edge1 - edge0)).clamped
    return Double(t * t * (3 - 2 * t))
}

extension CGFloat {
    var clamped: CGFloat { Swift.min(Swift.max(self, 0), 1) }
}
