import CoreGraphics
import SwiftUI
import Testing
@testable import Mantle

/// Where the collapsed bar sits for each tab bar arrangement, and that it morphs
/// into a full-width sheet.
@MainActor
struct MantleLayoutTests {
    private let collapsed = MantleCollapsedLayout(height: 56, horizontalInset: 20, bottomInset: 8)

    private func layout(size: CGSize, safeBottom: CGFloat, tabBar: CGRect?) -> MantleLayout<Int> {
        MantleLayout(
            size: size,
            safeArea: EdgeInsets(top: 59, leading: 0, bottom: safeBottom, trailing: 0),
            tabBar: tabBar,
            collapsed: collapsed,
            cornerRadius: 38,
            entries: [
                .init(detent: .collapsed, content: [0]),
                .init(detent: .large, content: [1]),
            ],
            expandedContent: [],
            expandedCollapseMode: .automatic,
            revealMarkers: []
        )
    }

    private func collapsedFrame(_ layout: MantleLayout<Int>) -> CGRect {
        layout.frame(top: layout.restTop)
    }

    @Test func bottomTabBarPlacesTheBarAboveItAcrossTheWidth() {
        // iPhone 18 Pro, iOS 27 floating tab bar.
        let layout = layout(size: CGSize(width: 402, height: 874), safeBottom: 34, tabBar: CGRect(x: 21, y: 791, width: 360, height: 62))
        let bar = collapsedFrame(layout)
        #expect(bar.minX == CGFloat(20))
        #expect(bar.maxX == CGFloat(382))
        #expect(bar.maxY == CGFloat(791 - 8))
        #expect(bar.height == CGFloat(56))
    }

    @Test func noTabBarSitsAboveTheSafeArea() {
        let layout = layout(size: CGSize(width: 402, height: 874), safeBottom: 34, tabBar: nil)
        let bar = collapsedFrame(layout)
        #expect(bar.maxY == CGFloat(874 - 34 - 8))
        #expect(bar.width == CGFloat(402 - 40))
    }

    @Test(arguments: [
        CGSize(width: 669, height: 951),   // iPhone Duo, unfolded
        CGSize(width: 466, height: 678),   // iPhone Duo, folded
    ])
    func trailingVerticalTabBarKeepsTheBarAtTheBottomBesideIt(size: CGSize) {
        let rail = CGRect(x: size.width - 72, y: 120, width: 64, height: size.height - 240)
        let layout = layout(size: size, safeBottom: 20, tabBar: rail)
        let bar = collapsedFrame(layout)
        // At the bottom of the screen, not attached to the tab bar's top.
        #expect(bar.maxY == size.height - 20 - 8)
        // Across the content area, clear of the tab bar.
        #expect(bar.minX == 20)
        #expect(bar.maxX == rail.minX - 20)
        // The collapsed content is laid out at the bar's size.
        let content = layout.contentSize(for: layout.entries[0])
        #expect(content.width == bar.width)
        // Expanded, it's a full-width sheet covering the tab bar.
        let sheet = layout.placement(top: layout.largestTop).frame
        #expect(sheet.minX == 0)
        #expect(sheet.width == size.width)
    }

    @Test func leadingVerticalTabBarMirrors() {
        let size = CGSize(width: 669, height: 951)
        let rail = CGRect(x: 8, y: 120, width: 64, height: 711)
        let bar = collapsedFrame(layout(size: size, safeBottom: 20, tabBar: rail))
        #expect(bar.minX == rail.maxX + 20)
        #expect(bar.maxX == size.width - 20)
    }

    @Test func morphGoesFromTheBarToFullWidth() {
        let size = CGSize(width: 669, height: 951)
        let rail = CGRect(x: 597, y: 120, width: 64, height: 711)
        let layout = layout(size: size, safeBottom: 20, tabBar: rail)
        let start = layout.placement(top: layout.restTop, morph: 0).frame
        #expect(start == collapsedFrame(layout))
        let end = layout.placement(top: layout.largestTop, morph: 1).frame
        #expect(end.minX == 0 && end.width == size.width)
        // Halfway, it's between the two on both sides.
        let mid = layout.placement(top: (layout.restTop + layout.largestTop) / 2, morph: 0.5).frame
        #expect(mid.minX > 0 && mid.minX < start.minX)
        #expect(mid.maxX > start.maxX && mid.maxX < size.width)
    }
}
