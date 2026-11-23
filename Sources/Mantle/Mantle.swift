import SwiftUI

public extension View {
    /// Attaches a mantle: a surface that floats above the tab bar when collapsed
    /// and expands into a sheet, Apple Music style.
    ///
    /// See ``Detent`` for the ways to declare detents and their content.
    ///
    /// ```swift
    /// TabView { … }
    ///     .mantle(selection: $detent) {
    ///         Detent(.collapsed) { MiniPlayer() }
    ///         ScrollView {
    ///             Detent { Header() }
    ///             Detent { Controls() }
    ///             Queue()
    ///         }
    ///     }
    ///     .mantleBackground(.glass, expanded: .opaque)
    /// ```
    ///
    /// Apply it to the `TabView` itself (not a tab's content) so the expanded
    /// sheet covers the tab bar.
    ///
    /// - Parameters:
    ///   - isPresented: Whether the mantle is shown at all. When `false` it slides
    ///     away entirely (collapsed bar included) and stops insetting the content
    ///     beneath. Defaults to always shown.
    ///   - selection: The detent the mantle rests at.
    func mantle<Detents: View>(
        isPresented: Binding<Bool> = .constant(true),
        selection: Binding<MantleDetent>,
        @ViewBuilder detents: () -> Detents
    ) -> some View {
        MantleRoot(base: self, isPresented: isPresented.wrappedValue) {
            MantleEngineHost(selection: selection, isPresented: isPresented.wrappedValue, detents: detents())
        }
    }

    /// A two-state mantle: one view for the collapsed bar and one for the expanded
    /// sheet. `detents` are extra snap points; the expanded content is laid out at
    /// the largest detent and progressively revealed by smaller ones. Reveal
    /// markers (`Detent { … }`) inside `expanded` add content-sized snap points.
    ///
    /// ```swift
    /// .mantle(selection: $detent) {
    ///     MiniPlayer()
    /// } expanded: {
    ///     NowPlaying()
    /// }
    /// ```
    func mantle<Collapsed: View, Expanded: View>(
        isPresented: Binding<Bool> = .constant(true),
        selection: Binding<MantleDetent>,
        detents: [MantleDetent] = [],
        @ViewBuilder collapsed: () -> Collapsed,
        @ViewBuilder expanded: () -> Expanded
    ) -> some View {
        mantle(isPresented: isPresented, selection: selection) {
            Detent(.collapsed, content: collapsed)
            ForEach(detents.filter { !$0.isCollapsed && !$0.isReveal }, id: \.self) { Detent($0) }
            expanded()
        }
    }

    /// A mantle that manages its own detent. Use ``SwiftUICore/EnvironmentValues/mantle``
    /// from inside the detents to move it.
    func mantle<Detents: View>(
        isPresented: Binding<Bool> = .constant(true),
        @ViewBuilder detents: () -> Detents
    ) -> some View {
        MantleRoot(base: self, isPresented: isPresented.wrappedValue) {
            MantleStateHost(isPresented: isPresented.wrappedValue, detents: detents())
        }
    }
}

/// Hosts the mantle over `base` and, like a tab view bottom accessory, adds the
/// collapsed bar to the bottom safe area of the content it floats over, so scroll
/// views can scroll their last rows clear of it.
///
/// Tab bar position and content insets each have a fallback chain:
/// 1. UIKit (`TabBarReader`, `.automatic` mode): measures the `UITabBar` and
///    insets every tab's view controller. SwiftUI safe-area changes don't reach
///    inside a `TabView`'s tabs, so this is what makes it automatic.
/// 2. SwiftUI (`mantleSafeAreaInset()` on each screen): screens inset themselves
///    and report their bottom safe-area edge, which inside a tab is the tab bar's
///    top. Used in `.manual` mode, or in `.automatic` mode if UIKit isn't found.
/// 3. Neither: the collapsed bar sits above the bottom safe area, and a SwiftUI
///    `safeAreaInset` on `base` insets content that isn't in a tab.
private struct MantleRoot<Base: View, Host: View>: View {
    let base: Base
    /// When `false` the mantle is removed (animated) and nothing is inset.
    let isPresented: Bool
    @ViewBuilder let host: Host

    @Environment(\.mantleConfiguration) private var configuration
    @State private var tabBar = TabBarReader.Measurement(frame: nil, insetsTabs: false)
    @State private var reporter = MantleEdgeReporter()

    var body: some View {
        let layout = configuration.collapsedLayout
        let inset = isPresented ? layout.height + layout.bottomInset : 0
        let automatic = configuration.contentInsetMode == .automatic
        let uikitInsets = automatic && tabBar.insetsTabs
        // While UIKit insets the tabs, the reported safe-area edge already includes
        // our inset; add it back to get the tab bar's top.
        let reportedTop = reporter.edge.map { uikitInsets ? $0 + inset : $0 }

        base
            .environment(\.mantleScreenContentInset, uikitInsets ? 0 : inset)
            .environment(\.mantleEdgeReporter, reporter)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Last resort, for hosts that aren't a TabView and screens that don't
                // inset themselves.
                Color.clear
                    .frame(height: automatic && !tabBar.insetsTabs && reporter.edge == nil ? inset : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .overlay {
                // Manual mode prefers what SwiftUI reports; automatic prefers UIKit.
                // A screen-reported edge is a bottom tab bar's top; as a frame:
                let reportedFrame = reportedTop.map { CGRect(x: 0, y: $0, width: 10_000, height: 1) }
                let tabBarFrame = automatic ? tabBar.frame ?? reportedFrame : reportedFrame ?? tabBar.frame
                if configuration.engine == .uiKit {
                    // Always present: the UIKit engine animates showing and hiding itself.
                    host.environment(\.mantleTabBarFrame, tabBarFrame)
                } else if isPresented {
                    host.environment(\.mantleTabBarFrame, tabBarFrame)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(configuration.animation, value: isPresented)
            .background {
                // The UIKit engine insets the tabs itself.
                TabBarReader(contentInset: automatic && configuration.engine == .swiftUI ? inset : 0) { measurement in
                    withAnimation(.smooth(duration: 0.3)) { tabBar = measurement }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }
}

extension EnvironmentValues {
    /// Frame of the visible tab bar in global coordinates, measured by `MantleRoot`.
    @Entry var mantleTabBarFrame: CGRect? = nil
}

private struct MantleStateHost<Detents: View>: View {
    @State private var selection: MantleDetent = .collapsed
    let isPresented: Bool
    let detents: Detents

    var body: some View {
        MantleEngineHost(selection: $selection, isPresented: isPresented, detents: detents)
    }
}

/// Picks the engine set with `.mantleEngine(_:)`.
private struct MantleEngineHost<Detents: View>: View {
    @Binding var selection: MantleDetent
    let isPresented: Bool
    let detents: Detents
    @Environment(\.mantleConfiguration.engine) private var engine

    var body: some View {
        switch engine {
        case .swiftUI: MantleHost(selection: $selection, detents: detents)
        case .uiKit: MantleUIKitHost(selection: $selection, isPresented: isPresented, detents: detents)
        }
    }
}

// MARK: - Host

/// Live drag and snap state. Per-frame changes stay out of `MantleHost`, whose
/// render re-resolves the detent subviews and rebuilds the layout, and out of the
/// selection binding, which re-renders whatever owns it. Those expensive updates
/// happen once a snap has landed, when nothing is moving.
///
/// Observed per property: `MantleSurfaceDriver` reads `top`; `MantleSurface`
/// reads `isActive` and `snapFade`. The host reads none of them.
@MainActor @Observable
final class MantleDragModel {
    /// The surface's top edge while dragging or snapping; `nil` at rest.
    var top: CGFloat?
    /// Dragging or snapping.
    var isActive = false
    /// A finger is dragging the surface.
    var isDragging = false
    /// Cross-fade restriction for the current snap (see `fadeDetents`).
    var snapFade: Set<MantleDetent>?
    @ObservationIgnored var startTop: CGFloat?
    /// The translation when the drag was recognised, so the sheet doesn't jump by
    /// the recognition distance.
    @ObservationIgnored var startTranslation: CGFloat = 0
    /// Bumped by every snap, so a superseded snap's completion does nothing.
    @ObservationIgnored var snapID = 0
}

/// Feeds the surface its top edge: the drag model's while dragging or snapping,
/// otherwise the host's resting top. It's the only view that reads `drag.top`,
/// so per-frame changes re-render just this and the surface. Everything else the
/// surface needs is built by the host, outside `surface`, so it's identical from
/// frame to frame.
private struct MantleSurfaceDriver: View {
    let drag: MantleDragModel
    let restingTop: CGFloat
    let surface: (CGFloat) -> MantleSurface

    var body: some View {
        surface(drag.top ?? restingTop)
    }
}

/// Owns interaction state; resolves geometry and the declared detents.
struct MantleHost<Detents: View>: View {
    @Binding var selection: MantleDetent
    let detents: Detents

    @Environment(\.mantleConfiguration) private var configuration

    /// The detent the surface rests at. Tracks `selection`, but lets us choose the
    /// animation when `selection` is changed from outside.
    @State private var displayed: MantleDetent?
    @State private var drag = MantleDragModel()
    /// During programmatic moves, only these detents' content takes part in the
    /// cross-fade, so jumping collapsed → large doesn't flash the half content.
    @State private var fadeDetents: Set<MantleDetent>?
    @Environment(\.mantleTabBarFrame) private var tabBarFrame
    /// Measured reveal markers in the expanded content.
    @State private var revealMarkers: [MantleRevealMarker] = []

    var body: some View {
        // A GeometryReader that ignores the safe area reports zero insets, so derive
        // them from the difference between a safe and a full-screen reader.
        GeometryReader { safe in
            let safeFrame = safe.frame(in: .global)
            GeometryReader { proxy in
                let full = proxy.frame(in: .global)
                let safeArea = EdgeInsets(
                    top: max(0, safeFrame.minY - full.minY),
                    leading: max(0, safeFrame.minX - full.minX),
                    bottom: max(0, full.maxY - safeFrame.maxY),
                    trailing: max(0, full.maxX - safeFrame.maxX)
                )
                content(size: proxy.size, safeArea: safeArea, originY: full.minY)
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea(.keyboard)
    }

    private func content(size: CGSize, safeArea: EdgeInsets, originY: CGFloat) -> some View {
        Group(subviews: detents) { subviews in
            let (entries, expanded) = Self.entries(from: subviews)
            let layout = MantleLayout(
                size: size,
                safeArea: safeArea,
                tabBar: tabBarFrame.map { $0.offsetBy(dx: 0, dy: -originY) },
                collapsed: configuration.collapsedLayout,
                cornerRadius: configuration.cornerRadius,
                entries: entries,
                expandedContent: expanded,
                expandedCollapseMode: expanded.lazy.map(\.containerValues.mantleCollapseMode).first { $0 != .automatic } ?? .automatic,
                revealMarkers: revealMarkers
            )
            if !layout.entries.isEmpty {
                surface(layout: layout)
            }
        }
    }

    private func surface(layout: MantleLayout<Subview>) -> some View {
        let current = layout.resolve(displayed ?? selection)
        let restingTop = layout.top(for: current)
        let draggable = configuration.grabber != .hidden && layout.entries.count > 1
        let atLargest = current == layout.entries.last?.detent

        // Built once per host render, not per frame: a new proxy every frame would
        // change the environment and re-render every view that reads it.
        let proxy = MantleProxy(
            detent: current,
            detents: layout.entries.map(\.detent),
            move: { move(to: $0, layout: layout) }
        )
        let tap = {
            let destination = configuration.tapDestination.map(layout.resolve) ?? layout.entries.last!.detent
            move(to: destination, layout: layout)
        }
        let onRevealMarkersChange: ([MantleRevealMarker]) -> Void = { markers in
            // At the largest detent the content may be scrolled, which moves the
            // markers; keep the snap points from before scrolling started.
            guard !atLargest || revealMarkers.isEmpty, markers != revealMarkers else { return }
            revealMarkers = markers
        }
        let hostFades = fadeDetents

        return MantleSurfaceDriver(drag: drag, restingTop: restingTop) { top in
            MantleSurface(
                top: top,
                drag: drag,
                layout: layout,
                current: current,
                fadeDetents: hostFades,
                configuration: configuration,
                showsGrabber: draggable,
                proxy: proxy,
                tap: tap,
                onRevealMarkersChange: onRevealMarkersChange
            )
        }
        .gesture(dragGesture(layout: layout, start: current, restingTop: restingTop), isEnabled: draggable)
        .onChange(of: selection) { _, newValue in
            // Changed from outside (our own snaps set `displayed` first).
            let target = layout.resolve(newValue)
            guard target != displayed else { return }
            let from = displayed ?? current
            cancelSnap()
            fadeDetents = [from, target]
            withAnimation(configuration.animation) {
                displayed = target
                drag.top = nil
            }
        }
    }

    /// Moves via the proxy or a tap: snaps like a released drag, so only the
    /// surface renders while it moves.
    private func move(to detent: MantleDetent, layout: MantleLayout<Subview>) {
        let target = layout.resolve(detent)
        let current = layout.resolve(displayed ?? selection)
        guard target != current || drag.top != nil else { return }
        snap(
            from: drag.top ?? layout.top(for: current),
            to: target,
            layout: layout,
            fade: [current, target],
            animation: configuration.animation
        )
    }

    /// Animates the drag model from `top` to `target`. Only the surface renders
    /// while it moves; the host, the selection binding and the fades are updated
    /// once it lands.
    private func snap(from top: CGFloat, to target: MantleDetent, layout: MantleLayout<Subview>, fade: Set<MantleDetent>?, animation: Animation) {
        drag.snapID += 1
        let id = drag.snapID
        drag.startTop = nil
        drag.isActive = true
        drag.isDragging = false
        drag.snapFade = fade
        drag.top = top
        // `.removed`: only once the spring has completely stopped, so the expensive
        // updates below can't hitch a frame that's still moving. Nothing visible
        // waits for this: the surface derives its rest state from its position.
        withAnimation(animation, completionCriteria: .removed) {
            drag.top = layout.top(for: target)
        } completion: {
            guard drag.snapID == id else { return }
            // `drag.top` and the new resting top are equal, so nothing moves.
            fadeDetents = nil
            displayed = target
            if selection != target { selection = target }
            drag.top = nil
            drag.snapFade = nil
            drag.isActive = false
        }
    }

    private func cancelSnap() {
        drag.snapID += 1
        drag.snapFade = nil
        drag.isActive = false
        drag.isDragging = false
    }

    // MARK: Dragging

    private func dragGesture(layout: MantleLayout<Subview>, start: MantleDetent, restingTop: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                let startTop = drag.startTop ?? (drag.top ?? restingTop)
                if drag.startTop == nil {
                    // Once per drag (cancels any snap still running).
                    drag.snapID += 1
                    drag.startTop = startTop
                    drag.startTranslation = value.translation.height
                    drag.isActive = true
                    drag.isDragging = true
                    drag.snapFade = nil
                }
                // Every frame: only the driver and surface read this. Measured from
                // where the drag was recognised, so the sheet doesn't jump.
                drag.top = layout.rubberBanded(startTop + value.translation.height - drag.startTranslation)
            }
            .onEnded { value in
                release(top: drag.top ?? restingTop, velocity: value.velocity.height, from: start, layout: layout)
            }
    }

    /// Ends a drag that started at `start`, released at `top` moving at `velocity`
    /// (points per second): snaps to the detent a flick would carry it to.
    private func release(top: CGFloat, velocity: CGFloat, from start: MantleDetent, layout: MantleLayout<Subview>) {
        // Project where a flick would carry the surface, then pick the closest detent.
        let projected = top + velocity * 0.18
        let nearest = layout.entries.min { abs($0.top - projected) < abs($1.top - projected) }!
        let target = layout.settle(from: start, proposed: nearest)

        let distance = target.top - top
        let relativeVelocity = abs(distance) > 1 ? velocity / distance : 0
        snap(
            from: top,
            to: target.detent,
            layout: layout,
            // Jumping past intermediate detents: fade only between the two ends.
            fade: target.detent != nearest.detent ? [start, target.detent] : nil,
            animation: .interpolatingSpring(
                duration: 0.5,
                bounce: 0.12,
                initialVelocity: min(max(relativeVelocity, -30), 30)
            )
        )
    }

    // MARK: Entries

    /// Splits the builder's subviews into declared detents and unmarked
    /// (expanded) content.
    private static func entries(from subviews: SubviewsCollection) -> ([MantleLayout<Subview>.Entry], [Subview]) {
        var seen = Set<MantleDetent>()
        var result: [MantleLayout<Subview>.Entry] = []
        var expanded: [Subview] = []
        for subview in subviews {
            let values = subview.containerValues
            guard let detent = values.mantleDetent else {
                expanded.append(subview)
                continue
            }
            guard seen.insert(detent).inserted else { continue }
            result.append(.init(
                detent: detent,
                content: values.mantleDetentHasContent ? [subview] : [],
                collapseMode: values.mantleCollapseMode
            ))
        }
        return (result, expanded)
    }
}
