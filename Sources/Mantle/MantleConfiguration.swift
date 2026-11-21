import SwiftUI
import UIKit

/// What the mantle's surface is drawn with.
///
/// Every background has a SwiftUI form (used by the SwiftUI engine) and a UIKit
/// form (used by ``MantleViewController`` and the UIKit engine). The SwiftUI
/// constructors map to UIKit as closely as the types allow: `Glass` by equality
/// (`.regular`, `.clear`; a tint can't be read back, so tinted glass becomes
/// plain regular glass in UIKit), `Material` by kind, `Color` directly, and other
/// shape styles to the system background colour. The `uiKit:` constructors give
/// an exact UIKit background and map back to SwiftUI.
public struct MantleBackground {
    enum Kind {
        case glass(Glass)
        case material(Material)
        case style(AnyShapeStyle)
    }

    enum UIKitKind {
        case glass(UIGlassEffect.Style, tint: UIColor?)
        case blur(UIBlurEffect.Style)
        case color(UIColor)
    }

    let kind: Kind
    let uiKit: UIKitKind

    /// Regular Liquid Glass.
    public static var glass: MantleBackground { .glass(.regular) }
    /// Liquid Glass with a custom variant, e.g. `.glass(.regular.tint(.pink))` or `.glass(.clear)`.
    public static func glass(_ glass: Glass) -> MantleBackground {
        .init(kind: .glass(glass), uiKit: .glass(glass == .clear ? .clear : .regular, tint: nil))
    }
    /// Liquid Glass, specified for UIKit (and mapped to SwiftUI's `Glass`).
    public static func glass(uiKit style: UIGlassEffect.Style, tint: UIColor? = nil) -> MantleBackground {
        var glass: Glass = style == .clear ? .clear : .regular
        if let tint { glass = glass.tint(Color(uiColor: tint)) }
        return .init(kind: .glass(glass), uiKit: .glass(style, tint: tint))
    }

    /// A regular blur material.
    public static var blur: MantleBackground { .blur(.regular) }
    /// A blur material, e.g. `.blur(.ultraThin)`.
    public static func blur(_ material: Material) -> MantleBackground {
        .init(kind: .material(material), uiKit: .blur(Self.blurStyle(for: material)))
    }
    /// A blur, specified for UIKit (and mapped to the closest SwiftUI `Material`).
    public static func blur(uiKit style: UIBlurEffect.Style) -> MantleBackground {
        let material: Material = switch style {
        case .systemUltraThinMaterial: .ultraThin
        case .systemThinMaterial: .thin
        case .systemThickMaterial: .thick
        case .systemChromeMaterial: .bar
        default: .regular
        }
        return .init(kind: .material(material), uiKit: .blur(style))
    }

    /// The system background colour.
    public static var opaque: MantleBackground { .opaque(Color(uiColor: .systemBackground)) }
    /// Any opaque (or not) shape style: a colour, gradient, etc. Colours carry over
    /// to UIKit; other styles use the system background colour there.
    public static func opaque<S: ShapeStyle>(_ style: S) -> MantleBackground {
        let color: UIColor = (style as? Color).map { UIColor($0) } ?? .systemBackground
        return .init(kind: .style(AnyShapeStyle(style)), uiKit: .color(color))
    }
    /// A colour, specified for UIKit (and mapped to SwiftUI).
    public static func opaque(uiKit color: UIColor) -> MantleBackground {
        .init(kind: .style(AnyShapeStyle(Color(uiColor: color))), uiKit: .color(color))
    }

    var isGlass: Bool {
        if case .glass = kind { true } else { false }
    }

    /// `Material` isn't introspectable, so match it against the known materials.
    private static func blurStyle(for material: Material) -> UIBlurEffect.Style {
        let known: [(Material, UIBlurEffect.Style)] = [
            (.ultraThin, .systemUltraThinMaterial),
            (.thin, .systemThinMaterial),
            (.regular, .systemMaterial),
            (.thick, .systemThickMaterial),
            (.ultraThick, .systemThickMaterial),
            (.bar, .systemChromeMaterial),
        ]
        let description = String(describing: material)
        return known.first { String(describing: $0.0) == description }?.1 ?? .systemMaterial
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
    var spring = Spring(duration: 0.5, bounce: 0.12)
    var collapseSpring = Spring(duration: 0.3, bounce: 0.06)
    var contentInsetMode: MantleContentInsetMode = .automatic
    var engine: MantleEngine = .swiftUI
}

/// What renders and animates a SwiftUI `.mantle`.
public enum MantleEngine: Sendable, Equatable {
    /// SwiftUI views and animations.
    case swiftUI
    /// A UIKit ``MantleViewController``: the sheet is a UIKit view that moves with
    /// Core Animation springs on the render server, at the display's full refresh
    /// rate, and with a `UIPanGestureRecognizer` that cooperates with scroll views
    /// (pull to dismiss from the top of a list). Detent content stays SwiftUI,
    /// hosted in `UIHostingController`s that receive the surrounding environment.
    case uiKit
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

    /// Which engine renders and animates the mantle. Defaults to `.swiftUI`.
    func mantleEngine(_ engine: MantleEngine) -> some View {
        transformEnvironment(\.mantleConfiguration) { $0.engine = engine }
    }

    /// The springs the UIKit engine moves with (taps, proxy moves, snaps after a
    /// drag, which start at the finger's velocity). `collapse` is used for moves
    /// into the collapsed bar, which read best quick and nearly bounce-free.
    /// Defaults: `Spring(duration: 0.5, bounce: 0.12)` and
    /// `Spring(duration: 0.3, bounce: 0.06)`. The SwiftUI engine uses
    /// ``SwiftUICore/View/mantleAnimation(_:)``.
    func mantleSpring(_ spring: Spring, collapse: Spring? = nil) -> some View {
        transformEnvironment(\.mantleConfiguration) {
            $0.spring = spring
            if let collapse { $0.collapseSpring = collapse }
        }
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
    /// Live actions, for proxies whose detent list may be out of date (the UIKit
    /// controller's): they go straight to the current smallest / largest detent.
    let collapseAction: (@MainActor () -> Void)?
    let expandAction: (@MainActor () -> Void)?

    nonisolated init(
        detent: MantleDetent = .collapsed,
        detents: [MantleDetent] = [],
        move: @escaping @MainActor (MantleDetent) -> Void = { _ in },
        collapse: (@MainActor () -> Void)? = nil,
        expand: (@MainActor () -> Void)? = nil
    ) {
        self.detent = detent
        self.detents = detents
        self.move = move
        self.collapseAction = collapse
        self.expandAction = expand
    }

    /// Animates to `detent`. Ignored if the mantle has no content for it.
    public func move(to detent: MantleDetent) { move(detent) }
    /// Animates to the smallest detent.
    public func collapse() {
        if let collapseAction { collapseAction() } else if let first = detents.first { move(first) }
    }
    /// Animates to the largest detent.
    public func expand() {
        if let expandAction { expandAction() } else if let last = detents.last { move(last) }
    }
}

extension MantleProxy: Equatable {
    /// Compares the state, not the action: an equal proxy never invalidates the
    /// views that read it from the environment.
    public nonisolated static func == (lhs: MantleProxy, rhs: MantleProxy) -> Bool {
        lhs.detent == rhs.detent && lhs.detents == rhs.detents
    }
}

extension EnvironmentValues {
    /// The enclosing mantle. Outside a mantle, actions do nothing.
    @Entry public var mantle = MantleProxy()
}
