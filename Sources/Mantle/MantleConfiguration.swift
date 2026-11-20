import SwiftUI

/// What the mantle's surface is drawn with.
public struct MantleBackground {
    enum Kind {
        case glass(Glass)
        case material(Material)
        case style(AnyShapeStyle)
    }

    let kind: Kind

    /// Regular Liquid Glass.
    public static var glass: MantleBackground { .glass(.regular) }
    /// Liquid Glass with a custom variant, e.g. `.glass(.regular.tint(.pink))` or `.glass(.clear)`.
    public static func glass(_ glass: Glass) -> MantleBackground { .init(kind: .glass(glass)) }

    /// A regular blur material.
    public static var blur: MantleBackground { .blur(.regular) }
    /// A blur material, e.g. `.blur(.ultraThin)`.
    public static func blur(_ material: Material) -> MantleBackground { .init(kind: .material(material)) }

    /// The system background colour.
    public static var opaque: MantleBackground { .opaque(Color(uiColor: .systemBackground)) }
    /// Any opaque (or not) shape style: a colour, gradient, etc.
    public static func opaque<S: ShapeStyle>(_ style: S) -> MantleBackground { .init(kind: .style(AnyShapeStyle(style))) }

    var isGlass: Bool {
        if case .glass = kind { true } else { false }
    }
}

/// Geometry of the `.collapsed` floating bar.
public struct MantleCollapsedLayout: Sendable, Equatable {
    /// Height of the bar.
    public var height: CGFloat
    /// Inset from the leading and trailing screen edges.
    public var horizontalInset: CGFloat
    /// Gap between the bottom of the bar and the top of the tab bar. The tab bar
    /// is measured live, so this tracks it on every device. When there's no
    /// visible tab bar, it's the gap above the bottom safe-area edge instead.
    public var bottomInset: CGFloat

    public init(height: CGFloat = 56, horizontalInset: CGFloat = 20, bottomInset: CGFloat = 8) {
        self.height = height
        self.horizontalInset = horizontalInset
        self.bottomInset = bottomInset
    }

    public static let tabBar = MantleCollapsedLayout()
}

struct MantleConfiguration {
    var background: MantleBackground = .glass
    var expandedBackground: MantleBackground? = nil
    var grabber: Visibility = .automatic
    var collapsedLayout: MantleCollapsedLayout = .tabBar
    var cornerRadius: CGFloat = 38
    var dimsBackground: Bool = true
    var tapDestination: MantleDetent? = nil
    var animation: Animation = .spring(duration: 0.5, bounce: 0.12)
    var contentInsetMode: MantleContentInsetMode = .automatic
}

/// How the content under the mantle is inset so it can scroll clear of the
/// collapsed bar.
public enum MantleContentInsetMode: Sendable, Equatable {
    /// The mantle insets it for you. In a `TabView` this adds the collapsed bar to
    /// every tab's bottom safe area via the tab bar's UIKit view controllers (the
    /// way a tab view bottom accessory does). If that isn't available, screens
    /// that apply ``SwiftUICore/View/mantleSafeAreaInset()`` are inset in SwiftUI;
    /// failing that, a SwiftUI `safeAreaInset` is applied to the mantle's host.
    case automatic
    /// The mantle doesn't inset anything through UIKit. Apply
    /// ``SwiftUICore/View/mantleSafeAreaInset()`` to each screen's content: it
    /// insets the screen and reports the tab bar's position, in plain SwiftUI.
    /// (The UIKit tab bar measurement is only used if no screen reports in.)
    case manual
}

extension EnvironmentValues {
    @Entry var mantleConfiguration = MantleConfiguration()
}

public extension View {
    /// Sets the mantle's surface. Pass `expanded:` to cross-fade to a different
    /// background as it opens — e.g. glass when collapsed, opaque when expanded,
    /// like Apple Music.
    func mantleBackground(_ background: MantleBackground, expanded: MantleBackground? = nil) -> some View {
        transformEnvironment(\.mantleConfiguration) {
            $0.background = background
            $0.expandedBackground = expanded
        }
    }

    /// Shows or hides the grabber.
    ///
    /// With a grabber (`.visible` / `.automatic`) the mantle behaves like a sheet:
    /// it can be dragged between detents. With `.hidden` it is a tap target only —
    /// tapping the collapsed bar animates it open, and you move it between
    /// detents programmatically (via the selection binding or
    /// ``SwiftUICore/EnvironmentValues/mantle``).
    func mantleGrabber(_ visibility: Visibility) -> some View {
        transformEnvironment(\.mantleConfiguration) { $0.grabber = visibility }
    }

    /// Positions the `.collapsed` floating bar.
    func mantleCollapsedLayout(_ layout: MantleCollapsedLayout) -> some View {
        transformEnvironment(\.mantleConfiguration) { $0.collapsedLayout = layout }
    }

    /// Positions the `.collapsed` floating bar.
    func mantleCollapsedLayout(height: CGFloat = 56, horizontalInset: CGFloat = 20, bottomInset: CGFloat = 8) -> some View {
        mantleCollapsedLayout(.init(height: height, horizontalInset: horizontalInset, bottomInset: bottomInset))
    }

    /// Corner radius of the expanded sheet. (The collapsed bar is always a capsule.)
    func mantleCornerRadius(_ radius: CGFloat) -> some View {
        transformEnvironment(\.mantleConfiguration) { $0.cornerRadius = radius }
    }

    /// Whether the content behind the mantle dims while it is expanded. Tapping
    /// the dimmed area collapses the mantle.
    func mantleDimming(_ enabled: Bool) -> some View {
        transformEnvironment(\.mantleConfiguration) { $0.dimsBackground = enabled }
    }

    /// The detent tapping the collapsed bar opens to. Defaults to the largest detent.
    func mantleTapDestination(_ detent: MantleDetent) -> some View {
        transformEnvironment(\.mantleConfiguration) { $0.tapDestination = detent }
    }

    /// How the content under the mantle is inset to scroll clear of the collapsed
    /// bar. Defaults to `.automatic`.
    func mantleContentInsetMode(_ mode: MantleContentInsetMode) -> some View {
        transformEnvironment(\.mantleConfiguration) { $0.contentInsetMode = mode }
    }

    /// Makes this screen work with the mantle in plain SwiftUI, with no UIKit:
    /// - adds the collapsed bar to its bottom safe area, so scroll views inside
    ///   can scroll clear of it;
    /// - measures its bottom safe-area edge (inside a tab, the top of the tab bar)
    ///   and reports it to the mantle, which positions the collapsed bar above it.
    ///
    /// In `.manual` mode this is the only mechanism. In `.automatic` mode it's a
    /// fallback that kicks in if the mantle can't reach the tab bar through UIKit;
    /// while it can, the modifier adds no inset, so it never doubles up. Adding it
    /// to every screen makes an app independent of how `TabView` is built.
    ///
    /// Apply it to the screen's root view (one that fills the screen, such as a
    /// `ScrollView`, `List` or `Form`).
    /// SwiftUI safe-area changes don't cross a `TabView` tab or a `NavigationStack`,
    /// so apply it *inside* the navigation stack, to every screen (including pushed
    /// ones):
    ///
    /// ```swift
    /// Tab("Home", systemImage: "house") {
    ///     NavigationStack {
    ///         Home()
    ///             .mantleSafeAreaInset()
    ///             .navigationDestination(for: Album.self) { album in
    ///                 AlbumView(album).mantleSafeAreaInset()
    ///             }
    ///     }
    /// }
    /// ```
    func mantleSafeAreaInset() -> some View {
        modifier(MantleSafeAreaInsetModifier())
    }

    /// The animation used for programmatic and tap-driven detent changes.
    func mantleAnimation(_ animation: Animation) -> some View {
        transformEnvironment(\.mantleConfiguration) { $0.animation = animation }
    }
}

/// Lets views inside a mantle read and change its detent.
///
/// ```swift
/// @Environment(\.mantle) private var mantle
/// Button("Close", systemImage: "chevron.down") { mantle.collapse() }
/// ```
@MainActor
public struct MantleProxy {
    /// The detent the mantle is resting at (or animating towards).
    public let detent: MantleDetent
    /// All detents the mantle can rest at, smallest first.
    public let detents: [MantleDetent]
    /// Whether the mantle is resting anywhere other than `.collapsed`.
    public var isExpanded: Bool { !detent.isCollapsed }
    let move: @MainActor (MantleDetent) -> Void

    nonisolated init(detent: MantleDetent = .collapsed, detents: [MantleDetent] = [], move: @escaping @MainActor (MantleDetent) -> Void = { _ in }) {
        self.detent = detent
        self.detents = detents
        self.move = move
    }

    /// Animates to `detent`. Ignored if the mantle has no content for it.
    public func move(to detent: MantleDetent) { move(detent) }
    /// Animates to the smallest detent.
    public func collapse() { if let first = detents.first { move(first) } }
    /// Animates to the largest detent.
    public func expand() { if let last = detents.last { move(last) } }
}

extension EnvironmentValues {
    /// The enclosing mantle. Outside a mantle, actions do nothing.
    @Entry public var mantle = MantleProxy()
}
