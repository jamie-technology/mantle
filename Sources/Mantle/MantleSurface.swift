import SwiftUI

/// Draws the mantle for a given top edge. Animatable on `top`, so every derived
/// property (frame, corner radius, cross-fades, background blend) follows the
/// same path whether the surface is being dragged, flicked or animated.
struct MantleSurface: View, Animatable {
    /// The top edge: resting, dragged, or animating (see `MantleSurfaceDriver`).
    var top: CGFloat
    let drag: MantleDragModel
    let layout: MantleLayout
    let current: MantleDetent
    let fadeDetents: Set<MantleDetent>?
    let configuration: MantleConfiguration
    let showsGrabber: Bool
    let proxy: MantleProxy
    let tap: () -> Void
    let onRevealMarkersChange: ([MantleRevealMarker]) -> Void

    nonisolated var animatableData: CGFloat {
        get { top }
        set { top = newValue }
    }

    var body: some View {
        let isDragging = drag.isDragging
        // Derived from the position, not the resting detent (which only updates once
        // a snap has fully stopped), so nothing visible waits for that.
        let atRestTop = abs(top - layout.restTop) < 4
        let atLargestTop = abs(top - layout.largestTop) < 4
        let scrollEnabled = atLargestTop && !isDragging
        let (frame, offset) = layout.placement(top: top)
        let expansion = layout.expansion(top: top)
        // While dragging or snapping, the drag model's fades apply.
        let opacities = layout.opacities(top: top, among: drag.top != nil ? drag.snapFade : fadeDetents)
        let shape = RoundedRectangle(cornerRadius: layout.cornerRadius(top: top), style: .continuous)
        let isAtRest = layout.hasCollapsed && atRestTop && !isDragging
        // Accessibility follows the settled detent, which only changes at rest, so it
        // never restructures the view mid-drag.
        let settledCollapsed = layout.hasCollapsed && current.isCollapsed
        let settledOpacities = layout.opacities(top: layout.top(for: current), among: nil)

        ZStack(alignment: .topLeading) {
            if configuration.dimsBackground, layout.hasCollapsed {
                Color.black
                    .opacity(0.25 * expansion)
                    .contentShape(.rect)
                    .onTapGesture { proxy.collapse() }
                    .allowsHitTesting(!atRestTop)
                    .accessibilityHidden(true)
            }

            ZStack(alignment: .top) {
                ForEach(layout.contentEntries, id: \.detent) { entry in
                    let opacity = opacities[entry.detent] ?? 0
                    let size = layout.contentSize(for: entry)
                    let insets = layout.contentInsets(for: entry, frameTop: top)
                    VStack(spacing: 0) {
                        ForEach(entry.content) { $0 }
                    }
                    .coordinateSpace(.named(MantleRevealKey.space))
                    .padding(insets)
                    // The surface lives in a container that ignores the safe area, so
                    // the content sees zero insets and `insets` above are the only ones.
                    // (Don't add `.ignoresSafeArea()` here: it grows the frame into the
                    // safe area whenever the sheet touches an edge.)
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .frame(width: frame.width, alignment: .top)
                    // Never fully 0: SwiftUI doesn't draw opacity-0 views, so the
                    // first frame they became visible would have to build their whole
                    // render tree, hitching the start of a drag.
                    .opacity(max(opacity, 0.001))
                    .allowsHitTesting(opacity > 0.5)
                    .accessibilityHidden((settledOpacities[entry.detent] ?? 0) < 0.5)
                }
            }
            .scrollDisabled(!scrollEnabled)
            .onPreferenceChange(MantleRevealKey.self) { markers in
                onRevealMarkersChange(markers)
            }
            .frame(width: frame.width, height: frame.height, alignment: .top)
            .overlay(alignment: .top) {
                if showsGrabber {
                    ZStack(alignment: .top) {
                        // Once expanded, the strip around the grabber always drags the
                        // sheet, even over a scrolling ScrollView. Always present (only
                        // its hit-testing changes) so the tree doesn't change mid-drag.
                        Color.clear
                            .frame(height: layout.grabberTop(frameTop: top) + 20)
                            .frame(maxWidth: .infinity)
                            .contentShape(.rect)
                            .allowsHitTesting(expansion > 0.5)
                        Capsule()
                            .fill(.secondary)
                            .frame(width: 36, height: 5)
                            .padding(.top, layout.grabberTop(frameTop: top))
                    }
                    .accessibilityHidden(true)
                }
            }
            .clipShape(shape)
            .modifier(MantleBackgroundModifier(
                collapsed: configuration.background,
                expanded: configuration.expandedBackground,
                expansion: layout.hasCollapsed ? expansion : 1,
                // Constant, never toggled: switching it rebuilds the glass, which hitched
                // the first frame of a drag. Only in tap-target mode, where there's no
                // drag for its own press-and-stretch recogniser to compete with.
                interactive: layout.hasCollapsed && !showsGrabber,
                shape: shape
            ))
            .contentShape(shape)
            // Always attached (checked when it fires) rather than enabled and
            // disabled, which would change the gesture graph as a drag starts.
            .gesture(TapGesture().onEnded { if isAtRest { tap() } })
            .accessibilityElement(children: settledCollapsed ? .combine : .contain)
            .accessibilityAddTraits(settledCollapsed ? .isButton : [])
            .accessibilityAction(named: "Expand") { proxy.expand() }
            .accessibilityAction(.escape) { proxy.collapse() }
            .position(x: frame.midX, y: frame.midY)
            // Render-time slide; see `MantleLayout.placement(top:)`.
            .offset(y: offset)
        }
        .environment(\.mantle, proxy)
    }
}

// MARK: - Background

private struct MantleBackgroundModifier<S: Shape>: ViewModifier {
    let collapsed: MantleBackground
    let expanded: MantleBackground?
    let expansion: CGFloat
    let interactive: Bool
    let shape: S

    func body(content: Content) -> some View {
        let expanded = expanded ?? collapsed
        // Glass can't be faded, so if either end is glass it becomes the base layer
        // and the other background fades over it.
        let glass: Glass? = switch (collapsed.kind, expanded.kind) {
        case (.glass(let a), .glass(let b)): expansion < 0.5 ? a : b
        case (.glass(let g), _), (_, .glass(let g)): g
        default: nil
        }
        let collapsedOpacity = collapsed.isGlass ? 0 : (expanded.isGlass ? 1 - expansion : 1)
        let expandedOpacity = expanded.isGlass ? 0 : expansion

        let layered = content
            .background {
                ZStack {
                    fill(collapsed).opacity(collapsedOpacity)
                    if expanded.kind.id != collapsed.kind.id || expanded.isGlass != collapsed.isGlass {
                        fill(expanded).opacity(expandedOpacity)
                    }
                }
                .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(glass == nil ? 0.18 * (1 - expansion) : 0), radius: 14, y: 6)

        if let glass {
            layered.glassEffect(glass.interactive(interactive), in: shape)
        } else {
            layered
        }
    }

    @ViewBuilder
    private func fill(_ background: MantleBackground) -> some View {
        switch background.kind {
        case .glass: Color.clear
        case .material(let material): shape.fill(material)
        case .style(let style): shape.fill(style)
        }
    }
}

private extension MantleBackground.Kind {
    /// Rough identity, only used to avoid stacking the same fill twice.
    var id: String {
        switch self {
        case .glass: "glass"
        case .material(let m): "material-\(m)"
        case .style(let s): "style-\(s)"
        }
    }
}
