import SwiftUI

/// A resting position for a mantle.
///
/// Detents are ordered by how much of the screen they cover. `.collapsed` is the
/// floating bar that sits above the tab bar; every other detent is a sheet
/// anchored to the bottom of the screen.
public struct MantleDetent: Hashable, Sendable, CustomStringConvertible {
    enum RevealID: Hashable, Sendable {
        case index(Int)
        case name(String)
    }

    enum Storage: Hashable, Sendable {
        case collapsed
        case fraction(CGFloat)
        case height(CGFloat)
        case large
        case fullScreen
        case reveal(RevealID)
    }

    let storage: Storage

    /// The floating bar above the tab bar (the "mini player").
    public static let collapsed = MantleDetent(storage: .collapsed)
    /// A sheet covering a quarter of the screen.
    public static let quarter = MantleDetent.fraction(0.25)
    /// A sheet covering half of the screen.
    public static let half = MantleDetent.fraction(0.5)
    /// A full-height sheet whose top edge sits just below the top safe area,
    /// like a SwiftUI `.large` sheet.
    public static let large = MantleDetent(storage: .large)
    /// Covers the entire screen, edge to edge, including the status bar area.
    public static let fullScreen = MantleDetent(storage: .fullScreen)

    /// A sheet covering `fraction` of the screen height (never taller than `.large`).
    public static func fraction(_ fraction: CGFloat) -> MantleDetent {
        MantleDetent(storage: .fraction(min(max(fraction, 0), 1)))
    }

    /// A sheet whose visible height, above the bottom safe area, is `height` points.
    public static func height(_ height: CGFloat) -> MantleDetent {
        MantleDetent(storage: .height(max(height, 0)))
    }

    /// The snap point defined by the `index`th unnamed reveal ``Detent`` in the
    /// expanded content, counting from the top (0 = first).
    public static func revealed(_ index: Int) -> MantleDetent {
        MantleDetent(storage: .reveal(.index(index)))
    }

    /// The snap point defined by `Detent(id: name) { … }` in the expanded content.
    public static func revealed(_ name: String) -> MantleDetent {
        MantleDetent(storage: .reveal(.name(name)))
    }

    public var isCollapsed: Bool { storage == .collapsed }

    var isReveal: Bool {
        if case .reveal = storage { true } else { false }
    }

    public var description: String {
        switch storage {
        case .collapsed: "collapsed"
        case .fraction(let f): "fraction(\(f))"
        case .height(let h): "height(\(h))"
        case .large: "large"
        case .fullScreen: "fullScreen"
        case .reveal(.index(let i)): "revealed(\(i))"
        case .reveal(.name(let n)): "revealed(\"\(n)\")"
        }
    }
}

extension ContainerValues {
    @Entry var mantleDetent: MantleDetent? = nil
    @Entry var mantleDetentHasContent: Bool = true
    @Entry var mantleCollapseMode: MantleCollapseMode = .automatic
}

/// Where the mantle goes when it's dragged down from a detent.
public enum MantleCollapseMode: Hashable, Sendable {
    /// For snap points without content of their own (content-less
    /// `Detent(.half)`s and reveal markers): the mode of the content they show,
    /// so dismissing that content behaves the same from any of its snap points.
    /// For everything else: `.nearest`. This is the default.
    case automatic
    /// Settle on the nearest smaller detent (velocity-projected). Use it to opt a
    /// snap point out of an inherited target.
    case nearest
    /// Any downward release that would land on a smaller detent goes straight to
    /// this detent instead, e.g. dismissing a full player back to the mini player
    /// rather than to `.half`. Only used when the target is smaller than the
    /// detent the drag started at.
    case target(MantleDetent)
}

public extension View {
    /// Where the mantle goes when it's dragged down from the detent this content
    /// lives at. Apply it to the unmarked expanded content (usually at `.large`).
    /// On a ``Detent``, ``Detent/mantleCollapseMode(_:)`` is used instead.
    ///
    /// ```swift
    /// .mantle(selection: $detent) {
    ///     Detent(.collapsed) { MiniPlayer() }
    ///     ScrollView { … }
    ///         .mantleCollapseMode(.target(.collapsed))
    /// }
    /// ```
    func mantleCollapseMode(_ mode: MantleCollapseMode) -> some View {
        containerValue(\.mantleCollapseMode, mode)
    }

    /// Shorthand for `.mantleCollapseMode(.target(target))`.
    func collapseTarget(_ target: MantleDetent) -> some View {
        mantleCollapseMode(.target(target))
    }
}

/// Declares a detent inside a ``SwiftUICore/View/mantle(selection:detents:)`` builder.
///
/// There are three flavours.
///
/// **Pinned content**: `Detent(.half) { … }` shows its own content at that
/// detent, laid out at the mantle's size there, cross-faded with neighbours.
///
/// **Snap point**: `Detent(.half)` has no content. It reveals the next larger
/// detent's content, laid out at that larger size.
///
/// **Reveal marker**: `Detent { … }` with no detent, placed *inside* the expanded
/// content (anywhere, including inside a `ScrollView`). The mantle measures it and
/// adds a snap point that shows the expanded content down to the bottom of this
/// group. Address it as `.revealed(0)`, `.revealed(1)`, … in document order, or
/// give it a name with `Detent(id:)`.
///
/// Any views in the builder that aren't wrapped in a `Detent` become the expanded
/// content, shown at the largest detent (an implicit `.large` if none is declared):
///
/// ```swift
/// .mantle(selection: $detent) {
///     Detent(.collapsed) { MiniPlayer() }
///     ScrollView {
///         Detent { Header() }            // first snap point
///         Detent { Controls() }          // second snap point
///         Queue()                        // revealed at .large, scrolls
///     }
/// }
/// ```
public struct Detent<Content: View>: View {
    enum Kind {
        case pinned(MantleDetent, hasContent: Bool)
        case reveal(name: String?)
    }

    let kind: Kind
    let content: Content
    var collapseMode: MantleCollapseMode = .automatic

    /// Where the mantle goes when it's dragged down from this detent. Works on
    /// pinned detents, snap points and reveal markers. See ``MantleCollapseMode``.
    ///
    /// ```swift
    /// ScrollView {
    ///     Detent { Header() }
    ///     Detent { Controls() }
    ///         .mantleCollapseMode(.nearest)   // step down to Header, despite the target below
    ///     Queue()
    /// }
    /// .collapseTarget(.collapsed)             // inherited by the Header marker
    /// ```
    public func mantleCollapseMode(_ mode: MantleCollapseMode) -> Detent {
        var copy = self
        copy.collapseMode = mode
        return copy
    }

    /// Shorthand for `.mantleCollapseMode(.target(target))`.
    public func collapseTarget(_ target: MantleDetent) -> Detent {
        mantleCollapseMode(.target(target))
    }

    /// Pins `content` to `detent`.
    public init(_ detent: MantleDetent, @ViewBuilder content: () -> Content) {
        self.kind = .pinned(detent, hasContent: true)
        self.content = content()
    }

    /// A reveal marker: a snap point that shows the expanded content down to the
    /// bottom of `content`. Use inside the expanded content.
    public init(id: String? = nil, @ViewBuilder content: () -> Content) {
        self.kind = .reveal(name: id)
        self.content = content()
    }

    public var body: some View {
        switch kind {
        case .pinned(let detent, let hasContent):
            // Wrap in a single container so multi-view content stays one subview.
            ZStack { content }
                .containerValue(\.mantleDetent, detent)
                .containerValue(\.mantleDetentHasContent, hasContent)
                .containerValue(\.mantleCollapseMode, collapseMode)
        case .reveal(let name):
            VStack(spacing: 0) { content }
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: MantleRevealKey.self,
                            value: [MantleRevealMarker(
                                name: name,
                                maxY: proxy.frame(in: .named(MantleRevealKey.space)).maxY,
                                collapseMode: collapseMode
                            )]
                        )
                    }
                }
        }
    }
}

public extension Detent where Content == EmptyView {
    /// A snap point with no content of its own; see ``Detent``.
    init(_ detent: MantleDetent) {
        self.kind = .pinned(detent, hasContent: false)
        self.content = EmptyView()
    }
}

struct MantleRevealMarker: Equatable, Sendable {
    var name: String?
    var maxY: CGFloat
    var collapseMode: MantleCollapseMode
}

struct MantleRevealKey: PreferenceKey {
    static let space = "mantle.reveal"
    static var defaultValue: [MantleRevealMarker] { [] }
    static func reduce(value: inout [MantleRevealMarker], nextValue: () -> [MantleRevealMarker]) {
        value.append(contentsOf: nextValue())
    }
}
