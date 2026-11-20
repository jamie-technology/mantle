import SwiftUI

/// Collects the bottom safe-area edges reported by `mantleSafeAreaInset()`
/// screens. Lives in the mantle's root and is passed down the environment, which
/// (unlike preferences) reaches inside `TabView` tabs and navigation stacks.
@MainActor @Observable
final class MantleEdgeReporter {
    /// The edge of the most recently shown reporting screen, in global coordinates.
    private(set) var edge: CGFloat?

    @ObservationIgnored private var edges: [UUID: CGFloat] = [:]
    @ObservationIgnored private var order: [UUID] = []

    func report(_ id: UUID, edge: CGFloat) {
        edges[id] = edge
        if !order.contains(id) { order.append(id) }
        refresh()
    }

    /// Called when a screen appears, so it becomes the one that counts.
    func bringToFront(_ id: UUID) {
        guard edges[id] != nil else { return }
        order.removeAll { $0 == id }
        order.append(id)
        refresh()
    }

    func remove(_ id: UUID) {
        edges[id] = nil
        order.removeAll { $0 == id }
        refresh()
    }

    private func refresh() {
        let latest = order.last.flatMap { edges[$0] }
        if latest != edge { edge = latest }
    }
}

extension EnvironmentValues {
    /// The inset `mantleSafeAreaInset()` applies: zero while the mantle insets the
    /// tabs through UIKit.
    @Entry var mantleScreenContentInset: CGFloat = 0
    /// Where `mantleSafeAreaInset()` reports its edge. `nil` outside a mantle.
    @Entry var mantleEdgeReporter: MantleEdgeReporter? = nil
}

struct MantleSafeAreaInsetModifier: ViewModifier {
    @Environment(\.mantleScreenContentInset) private var inset
    @Environment(\.mantleEdgeReporter) private var reporter
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // The inset view sits on the bottom safe-area edge, so its bottom is
                // that edge: inside a tab, the top of the tab bar.
                Color.clear
                    .frame(height: inset)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.frame(in: .global).maxY
                    } action: { edge in
                        reporter?.report(id, edge: edge)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .onAppear { reporter?.bringToFront(id) }
            .onDisappear { reporter?.remove(id) }
    }
}
