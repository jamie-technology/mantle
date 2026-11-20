import SwiftUI

/// Draws the mantle for a given top edge. Animatable on `top`, so every derived
/// property (frame, corner radius, cross-fades, background blend) follows the
/// same path whether the surface is being dragged, flicked or animated.
struct MantleSurface: View, Animatable {
    var top: CGFloat
    let layout: MantleLayout
    let current: MantleDetent
    let fadeDetents: Set<MantleDetent>?
    let configuration: MantleConfiguration
    let isDragging: Bool
    let showsGrabber: Bool
    /// Scroll views in the content only scroll at the largest detent; below it,
    /// drags move the sheet instead.
    let scrollEnabled: Bool
    let proxy: MantleProxy
    let tap: () -> Void
    let onRevealMarkersChange: ([MantleRevealMarker]) -> Void

    nonisolated var animatableData: CGFloat {
        get { top }
        set { top = newValue }
    }

    var body: some View {
        let frame = layout.frame(top: top)
        let expansion = layout.expansion(top: top)
        let opacities = layout.opacities(top: top, among: fadeDetents)
        let shape = RoundedRectangle(cornerRadius: layout.cornerRadius(top: top), style: .continuous)
        let isAtRest = layout.hasCollapsed && current.isCollapsed && !isDragging

        ZStack(alignment: .topLeading) {
            if configuration.dimsBackground, layout.hasCollapsed {
                Color.black
                    .opacity(0.25 * expansion)
                    .contentShape(.rect)
                    .onTapGesture { proxy.collapse() }
                    .allowsHitTesting(!current.isCollapsed && !isDragging)
                    .accessibilityHidden(true)
            }

            ZStack(alignment: .top) {
                ForEach(layout.contentEntries, id: \.detent) { entry in
                    let opacity = opacities[entry.detent] ?? 0
                    let size = layout.contentSize(for: entry)
                    let insets = layout.contentInsets(for: entry, frameTop: frame.minY)
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
                    .opacity(opacity)
                    .allowsHitTesting(opacity > 0.5)
                    .accessibilityHidden(opacity < 0.5)
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
                        // sheet, even over a scrolling ScrollView.
                        if expansion > 0.5 {
                            Color.clear
                                .frame(height: layout.grabberTop(frameTop: frame.minY) + 20)
                                .frame(maxWidth: .infinity)
                                .contentShape(.rect)
                        }
                        Capsule()
                            .fill(.secondary)
                            .frame(width: 36, height: 5)
                            .padding(.top, layout.grabberTop(frameTop: frame.minY))
                    }
                    .accessibilityHidden(true)
                }
            }
            .clipShape(shape)
            .modifier(MantleBackgroundModifier(
                collapsed: configuration.background,
                expanded: configuration.expandedBackground,
                expansion: layout.hasCollapsed ? expansion : 1,
                interactive: isAtRest,
                shape: shape
            ))
            .contentShape(shape)
            .gesture(TapGesture().onEnded(tap), isEnabled: isAtRest)
            .accessibilityElement(children: isAtRest ? .combine : .contain)
            .accessibilityAddTraits(isAtRest ? .isButton : [])
            .accessibilityAction(named: "Expand") { proxy.expand() }
            .accessibilityAction(.escape) { proxy.collapse() }
            // `position` (not `offset`) so content gets correct safe-area insets.
            .position(x: frame.midX, y: frame.midY)
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
