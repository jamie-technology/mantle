import SwiftUI
import UIKit

/// A snap point measured from the expanded content: the sheet shows the expanded
/// content down to `offset` points from its top (plus the home-indicator area).
/// The UIKit counterpart of a reveal marker (`Detent { … }`).
public struct MantleRevealPoint: Hashable, Sendable {
    /// Addresses it as `.revealed(id)`. Unnamed points are `.revealed(0)`,
    /// `.revealed(1)`, … from the top.
    public var id: String?
    public var offset: CGFloat
    public var collapseMode: MantleCollapseMode

    public init(id: String? = nil, offset: CGFloat, collapseMode: MantleCollapseMode = .automatic) {
        self.id = id
        self.offset = offset
        self.collapseMode = collapseMode
    }
}

/// A view in the expanded content whose bottom edge is a snap point: the sheet
/// shows the expanded content down to the bottom of `view`. The Auto Layout
/// friendly counterpart of ``MantleRevealPoint``: the mantle measures the view
/// after each layout pass and whenever its frame changes, in the coordinates of
/// any scroll view it's in (so scrolling never moves the snap point).
public struct MantleRevealView {
    /// Addresses it as `.revealed(id)`. Unnamed points are `.revealed(0)`,
    /// `.revealed(1)`, … from the top (counting reveal points and views together).
    public var id: String?
    public weak var view: UIView?
    public var collapseMode: MantleCollapseMode

    public init(id: String? = nil, view: UIView, collapseMode: MantleCollapseMode = .automatic) {
        self.id = id
        self.view = view
        self.collapseMode = collapseMode
    }
}

/// The UIKit mantle: a surface that floats above the tab bar as a capsule and
/// expands into a sheet, Apple Music style.
///
/// It's built for smoothness. A drag only updates a few layer properties per
/// touch, and snaps spring the sheet's top edge from a 120Hz display link, with
/// the same few property updates per frame. Content is laid out once at fixed
/// sizes (with Auto Layout, if you like), so moving the sheet never re-lays it out.
///
/// ```swift
/// let mantle = MantleViewController()
/// mantle.setContent(MiniPlayerViewController(), for: .collapsed)
/// mantle.expandedContent = NowPlayingViewController()
/// mantle.snapPoints = [.half]
/// mantle.install(in: tabBarController)
/// ```
///
/// For 120Hz on ProMotion iPhones, the app's Info.plist needs
/// `CADisableMinimumFrameDurationOnPhone = YES`.
@MainActor
public final class MantleViewController: UIViewController, UIGestureRecognizerDelegate {
    enum Slot: Hashable {
        case detent(MantleDetent)
        case expanded
    }

    // MARK: Public: content

    /// Shows `viewController` at `detent` (pinned content, cross-faded with its
    /// neighbours). Pass `nil` to remove it.
    public func setContent(_ viewController: UIViewController?, for detent: MantleDetent) {
        setSlot(.detent(detent), to: viewController)
    }

    /// Content shown at the largest detent (an implicit `.large` if none is
    /// declared) and progressively revealed by smaller snap points.
    public var expandedContent: UIViewController? {
        get { slots[.expanded]?.controller }
        set { setSlot(.expanded, to: newValue) }
    }

    /// Detents without content of their own: they reveal the next larger content.
    public var snapPoints: [MantleDetent] = [] { didSet { invalidateLayout() } }

    /// Snap points measured from the expanded content.
    public var revealPoints: [MantleRevealPoint] = [] { didSet { updateRevealMarkers() } }

    /// Views in the expanded content whose bottom edges are snap points; see
    /// ``MantleRevealView``. Combined with `revealPoints`.
    public var revealViews: [MantleRevealView] = [] {
        didSet {
            observeRevealViews()
            measureRevealViews()
        }
    }

    /// Where a drag down from `detent` goes. See ``MantleCollapseMode``.
    public func setCollapseMode(_ mode: MantleCollapseMode, for detent: MantleDetent) {
        collapseModes[detent] = mode
        invalidateLayout()
    }

    /// The collapse mode of the detent the expanded content lives at.
    public var expandedCollapseMode: MantleCollapseMode = .automatic { didSet { invalidateLayout() } }

    // MARK: Public: state

    /// The detent the mantle has settled at.
    public private(set) var detent: MantleDetent = .collapsed
    /// All resting detents, smallest first, including measured reveal points.
    public var detents: [MantleDetent] { layout?.entries.map(\.detent) ?? [] }
    /// Called when the mantle settles at a new detent.
    public var onDetentChange: ((MantleDetent) -> Void)?

    /// Moves to `detent`. Falls back to the resting detent if it doesn't exist.
    public func move(to detent: MantleDetent, animated: Bool = true) {
        guard let layout else {
            pendingDetent = detent
            return
        }
        // Reveal points appear once the content has been measured; remember the
        // request until then rather than falling back to the resting detent.
        if detent.isReveal, !layout.entries.contains(where: { $0.detent == detent }) {
            pendingDetent = detent
            return
        }
        pendingDetent = nil
        let target = layout.resolve(detent)
        let current = animatingTarget ?? self.detent
        guard target != current || animatingTarget != nil || isDragging else { return }
        if animated {
            snap(to: target, velocity: 0, fade: [current, target])
        } else {
            stopAnimation()
            apply(top: layout.top(for: target), fade: nil)
            settle(at: target)
        }
    }

    /// A proxy for this mantle, to put in the environment of hosted SwiftUI
    /// content: `UIHostingController(rootView: content.environment(\.mantle, mantle.proxy))`.
    /// Its actions always act on the mantle as it is now; `detent` and `detents`
    /// are as of when you read it.
    public var proxy: MantleProxy {
        MantleProxy(
            detent: detent,
            detents: detents,
            move: { [weak self] in self?.move(to: $0) },
            collapse: { [weak self] in self?.collapse() },
            expand: { [weak self] in self?.expand() }
        )
    }

    /// Animates to the smallest detent.
    public func collapse() { if let first = layout?.entries.first { move(to: first.detent) } }
    /// Animates to the largest detent.
    public func expand() { if let last = layout?.entries.last { move(to: last.detent) } }

    /// Whether the mantle is shown at all. Hiding it slides it away, collapsed bar
    /// included, and stops insetting the content beneath.
    public private(set) var isPresented = true

    public func setPresented(_ presented: Bool, animated: Bool = true) {
        guard presented != isPresented else { return }
        isPresented = presented
        updateContentInsets()
        let changes = { [self] in
            surface.alpha = presented ? 1 : 0
            surface.transform = presented
                ? CGAffineTransform(translationX: 0, y: currentPlacement.offset)
                : CGAffineTransform(translationX: 0, y: currentPlacement.offset + view.bounds.height - surface.frame.minY)
            dimView.alpha = presented ? dimAlpha(top: visualTop) : 0
        }
        if presented { surface.isHidden = false }
        let completion: (UIViewAnimatingPosition) -> Void = { [self] _ in
            if !isPresented { surface.isHidden = true }
        }
        if animated {
            let animator = UIViewPropertyAnimator(duration: spring.duration, timingParameters: UISpringTimingParameters(duration: spring.duration, bounce: spring.bounce))
            animator.addAnimations(changes)
            animator.addCompletion(completion)
            animator.startAnimation()
        } else {
            changes()
            completion(.end)
        }
    }

    // MARK: Public: appearance and behaviour

    public var background: MantleBackground = .glass { didSet { surface.configure(background: background, expanded: expandedBackground, interactiveGlass: interactiveGlass); applyCurrent() } }
    /// Cross-fades to this background as it opens (e.g. glass → opaque).
    public var expandedBackground: MantleBackground? { didSet { surface.configure(background: background, expanded: expandedBackground, interactiveGlass: interactiveGlass); applyCurrent() } }
    /// With a grabber the mantle is a draggable sheet; without one it's a tap target.
    public var showsGrabber = true {
        didSet {
            pan.isEnabled = showsGrabber
            surface.configure(background: background, expanded: expandedBackground, interactiveGlass: interactiveGlass)
            applyCurrent()
        }
    }
    /// Dims the content behind while expanded; tapping the dimmed area collapses.
    public var dimsBackground = true { didSet { applyCurrent() } }
    public var collapsedLayout = MantleCollapsedLayout() { didSet { updateContentInsets(); invalidateLayout() } }
    /// Corner radius of the expanded sheet (the collapsed bar is always a capsule).
    public var cornerRadius: CGFloat = 38 { didSet { invalidateLayout() } }
    /// Where tapping the collapsed bar goes. Defaults to the largest detent.
    public var tapDestination: MantleDetent?
    /// The spring for snaps, taps and programmatic moves.
    public var spring = Spring(duration: 0.5, bounce: 0.12)
    /// The spring for moves to and from the collapsed bar: quick, nearly
    /// bounce-free, Apple Music style.
    public var collapseSpring = Spring(duration: 0.3, bounce: 0.06)
    /// `.automatic` adds the collapsed bar to every tab's bottom safe area when
    /// installed in a `UITabBarController`.
    public var contentInsetMode: MantleContentInsetMode = .automatic { didSet { updateContentInsets() } }
    /// Whether a `UITapGestureRecognizer` expands the collapsed bar. The SwiftUI
    /// bridge turns this off and handles taps in SwiftUI, so buttons in the bar
    /// take precedence.
    var handlesTapToExpand = true

    // MARK: Public: installation

    /// Installs the mantle above `tabBarController`'s tab bar, and (in
    /// `.automatic` inset mode) insets every tab so it can scroll clear of the bar.
    public func install(in tabBarController: UITabBarController) {
        install(in: tabBarController as UIViewController)
        observeTabBar(tabBarController)
    }

    /// Installs the mantle over `parent`'s view.
    public func install(in parent: UIViewController) {
        uninstall()
        parent.addChild(self)
        view.frame = parent.view.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        parent.view.addSubview(view)
        didMove(toParent: parent)
        hostTabBarController = parent as? UITabBarController
        updateContentInsets()
    }

    public func uninstall() {
        guard parent != nil else { return }
        insetter.remove()
        tabBarObservations = []
        hostTabBarController = nil
        willMove(toParent: nil)
        view.removeFromSuperview()
        removeFromParent()
    }

    // MARK: Internals

    @MainActor private struct SlotContent {
        let controller: UIViewController
        let container = UIView()
    }

    private var slots: [Slot: SlotContent] = [:]
    private var collapseModes: [MantleDetent: MantleCollapseMode] = [:]
    var revealMarkers: [MantleRevealMarker] = [] { didSet { if revealMarkers != oldValue { invalidateLayout() } } }
    /// `revealViews`, as measured.
    private var measuredRevealPoints: [MantleRevealPoint] = []
    private var revealViewObservations: [NSKeyValueObservation] = []

    private(set) var layout: MantleLayout<Slot>?
    private var pendingDetent: MantleDetent?

    private let rootView = MantlePassthroughView()
    private let dimView = UIView()
    private let surface = MantleSurfaceView()
    private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))

    private let driver = MantleFrameDriver()
    /// Bumped by every snap, so a superseded snap stops.
    private var snapID = 0
    private var animatingTarget: MantleDetent?
    /// The top edge the model layers are set to (the target, while animating).
    private var visualTop: CGFloat = 0
    private var currentPlacement: (frame: CGRect, offset: CGFloat) = (.zero, 0)
    private var appliedFade: Set<MantleDetent>?

    private var isDragging = false
    private var dragStartTop: CGFloat = 0
    private var dragStartTranslation: CGFloat = 0
    private var dragFrom: MantleDetent = .collapsed
    private var panMode = PanMode.undecided
    private var panStartTranslation: CGFloat = 0
    private var lastTranslation: CGFloat = 0
    private weak var trackedScrollView: UIScrollView?

    private weak var hostTabBarController: UITabBarController?
    private var tabBarObservations: [NSKeyValueObservation] = []
    private let insetter = MantleTabInsetter()
    private var lastLayoutInputs: (CGSize, UIEdgeInsets, CGFloat?)?

    private var interactiveGlass: Bool { !showsGrabber }

    public override func loadView() {
        view = rootView
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        dimView.backgroundColor = .black
        dimView.alpha = 0
        dimView.isUserInteractionEnabled = false
        dimView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleDimTap)))
        view.addSubview(dimView)
        view.addSubview(surface)
        // Front to back: the sheet first, then the dimming behind it.
        rootView.hitTargets = [surface, dimView]

        pan.delegate = self
        pan.isEnabled = showsGrabber
        surface.addGestureRecognizer(pan)
        tap.delegate = self
        tap.cancelsTouchesInView = false
        surface.addGestureRecognizer(tap)

        surface.configure(background: background, expanded: expandedBackground, interactiveGlass: interactiveGlass)
        surface.onEscape = { [weak self] in self?.collapse() }
        surface.onExpandAction = { [weak self] in self?.expand() }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        dimView.frame = view.bounds
        rebuildLayoutIfNeeded()
        measureRevealViews()
    }

    // MARK: Reveal points

    private func updateRevealMarkers() {
        revealMarkers = (revealPoints + measuredRevealPoints).map {
            MantleRevealMarker(name: $0.id, maxY: $0.offset, collapseMode: $0.collapseMode)
        }
    }

    /// Measures `revealViews` in the expanded content's coordinates. Cheap, and a
    /// no-op when nothing moved.
    private func measureRevealViews() {
        guard !revealViews.isEmpty || !measuredRevealPoints.isEmpty else { return }
        var measured: [MantleRevealPoint] = []
        if let root = slots[.expanded]?.controller.view {
            root.layoutIfNeeded()
            for reveal in revealViews {
                guard let view = reveal.view, view.isDescendant(of: root) else { continue }
                measured.append(.init(id: reveal.id, offset: Self.bottom(of: view, in: root), collapseMode: reveal.collapseMode))
            }
        }
        guard measured != measuredRevealPoints else { return }
        measuredRevealPoints = measured
        updateRevealMarkers()
    }

    /// The bottom of `view` in `root`, as if any scroll view it's in were at its top.
    private static func bottom(of view: UIView, in root: UIView) -> CGFloat {
        var ancestor = view.superview
        while let current = ancestor, current !== root {
            if let scrollView = current as? UIScrollView, let container = scrollView.superview {
                // In the scroll view's bounds space, which is its content's coordinates.
                let inContent = view.convert(view.bounds, to: scrollView).maxY
                let origin = container.convert(scrollView.frame, to: root).minY
                return origin + scrollView.adjustedContentInset.top + inContent
            }
            ancestor = current.superview
        }
        return view.convert(view.bounds, to: root).maxY
    }

    /// Re-measures when a reveal view's frame changes (Auto Layout, Dynamic Type…).
    private func observeRevealViews() {
        let handler: @Sendable (Any, Any) -> Void = { [weak self] _, _ in
            DispatchQueue.main.async { self?.measureRevealViews() }
        }
        revealViewObservations = revealViews.compactMap(\.view).flatMap { view in
            [view.layer.observe(\.bounds, changeHandler: handler), view.layer.observe(\.position, changeHandler: handler)]
        }
    }

    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        view.setNeedsLayout()
    }

    // MARK: Layout

    private func invalidateLayout() {
        lastLayoutInputs = nil
        guard isViewLoaded else { return }
        view.setNeedsLayout()
    }

    private func tabBarTop() -> CGFloat? {
        guard let bar = hostTabBarController?.tabBar, !bar.isHidden, bar.alpha > 0.01, bar.window != nil else { return nil }
        return bar.convert(bar.bounds, to: view).minY
    }

    private func rebuildLayoutIfNeeded() {
        // The mantle covers the window, so the window's safe area is the one that
        // counts. (Inside a SwiftUI `TabView`'s tab bar controller, views report a
        // zero safe area: SwiftUI manages it itself.)
        let inputs = (view.bounds.size, view.window?.safeAreaInsets ?? view.safeAreaInsets, tabBarTop())
        if let last = lastLayoutInputs, last.0 == inputs.0, last.1 == inputs.1, last.2 == inputs.2, layout != nil { return }
        lastLayoutInputs = inputs
        guard view.bounds.width > 0 else { return }

        var entries: [MantleLayout<Slot>.Entry] = []
        var seen = Set<MantleDetent>()
        for (slot, _) in slots {
            guard case .detent(let detent) = slot, seen.insert(detent).inserted else { continue }
            entries.append(.init(detent: detent, content: [slot], collapseMode: collapseModes[detent] ?? .automatic))
        }
        for detent in snapPoints where seen.insert(detent).inserted {
            entries.append(.init(detent: detent, content: [], collapseMode: collapseModes[detent] ?? .automatic))
        }
        let insets = inputs.1
        let layout = MantleLayout<Slot>(
            size: inputs.0,
            safeArea: EdgeInsets(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right),
            tabBarTop: inputs.2,
            collapsed: collapsedLayout,
            cornerRadius: cornerRadius,
            entries: entries,
            expandedContent: slots[.expanded] != nil ? [.expanded] : [],
            expandedCollapseMode: expandedCollapseMode,
            revealMarkers: revealMarkers
        )
        guard !layout.entries.isEmpty else { return }
        self.layout = layout

        layoutSlots(layout)
        if let pending = pendingDetent, layout.entries.contains(where: { $0.detent == pending }) {
            // A requested detent that didn't exist yet (e.g. a reveal point waiting
            // to be measured) now does.
            pendingDetent = nil
            detent = pending
            if animatingTarget != nil || isDragging {
                stopAnimation()
                isDragging = false
            }
        } else {
            detent = layout.resolve(detent)
        }
        // A rebuild mid-animation or mid-drag keeps going; otherwise rest.
        if animatingTarget == nil, !isDragging {
            apply(top: layout.top(for: detent), fade: nil)
        }
    }

    /// Lays each slot's content out once, at its detent's size. Moving the sheet
    /// never changes these, so content is never re-laid out during motion.
    private func layoutSlots(_ layout: MantleLayout<Slot>) {
        let contentEntries = layout.contentEntries
        for (slot, content) in slots {
            guard let entry = contentEntries.first(where: { $0.content.first == slot }) else {
                content.container.isHidden = true
                continue
            }
            content.container.isHidden = false
            let size = layout.contentSize(for: entry)
            let insets = layout.contentInsets(for: entry, frameTop: entry.top)
            content.container.bounds = CGRect(origin: .zero, size: size)
            // Runs to the bottom edge: the home-indicator area is left to the
            // content's safe area, so scroll views scroll underneath it. (UIKit
            // content gets it from the window; the SwiftUI bridge passes it in.)
            content.controller.view.frame = CGRect(origin: .zero, size: size).inset(by: UIEdgeInsets(top: insets.top, left: insets.leading, bottom: 0, right: insets.trailing))
        }
    }

    private func setSlot(_ slot: Slot, to controller: UIViewController?) {
        if let existing = slots[slot] {
            guard existing.controller !== controller else { return }
            existing.controller.willMove(toParent: nil)
            existing.container.removeFromSuperview()
            existing.controller.view.removeFromSuperview()
            existing.controller.removeFromParent()
            slots[slot] = nil
        }
        if let controller {
            let content = SlotContent(controller: controller)
            addChild(controller)
            controller.view.backgroundColor = .clear
            content.container.addSubview(controller.view)
            content.container.alpha = 0
            surface.contentView.addSubview(content.container)
            controller.didMove(toParent: self)
            slots[slot] = content
        }
        invalidateLayout()
    }

    // MARK: Applying a position

    /// Sets every layer property for the sheet's top edge at `top`. Cheap: a few
    /// frames, a corner radius, alphas and a transform. Called per touch while
    /// dragging and per frame while snapping.
    /// A snap to or from the collapsed bar, which spreads the morph over its whole
    /// trip (see `MantleLayout.placement(top:morph:)`).
    private struct MorphSnap {
        /// The end of the trip that isn't the bar.
        let farTop: CGFloat
        /// How expanded the sheet is at `farTop`.
        let farExpansion: CGFloat
    }

    private func apply(top: CGFloat, fade: Set<MantleDetent>?, morph: MorphSnap? = nil) {
        guard let layout else { return }
        visualTop = top
        appliedFade = fade
        let placement: (frame: CGRect, offset: CGFloat)
        let expansion: CGFloat
        let cornerRadius: CGFloat
        let opacities: [MantleDetent: Double]
        if let morph, let rest = layout.entries.first, morph.farTop < layout.restTop - 1 {
            // Progress along the trip: 0 at the bar, 1 at the far end.
            let n = ((layout.restTop - top) / (layout.restTop - morph.farTop)).clamped
            let m = morph.farExpansion * n
            placement = layout.placement(top: top, morph: m)
            expansion = m
            cornerRadius = layout.cornerRadius(morph: m)
            // The bar's content shows over the first 30% of the trip back to it
            // (pinned at the card's top); the far content fades over the middle.
            let towardBar = 1 - n
            var fades = layout.opacities(top: morph.farTop, among: nil).mapValues { $0 * (1 - smoothstep(0.3, 0.8, towardBar)) }
            fades[rest.detent] = max(fades[rest.detent] ?? 0, smoothstep(0, 0.3, towardBar))
            opacities = fades
        } else {
            placement = layout.placement(top: top)
            expansion = layout.expansion(top: top)
            cornerRadius = layout.cornerRadius(top: top)
            opacities = layout.opacities(top: top, among: fade)
        }
        currentPlacement = placement
        let frame = placement.frame

        surface.bounds = CGRect(origin: .zero, size: frame.size)
        surface.center = CGPoint(x: frame.midX, y: frame.midY)
        if isPresented {
            surface.transform = CGAffineTransform(translationX: 0, y: placement.offset)
        }
        surface.apply(
            cornerRadius: cornerRadius,
            expansion: layout.hasCollapsed ? expansion : 1,
            showsGrabber: showsGrabber && layout.entries.count > 1,
            grabberTop: layout.grabberTop(frameTop: top)
        )
        dimView.alpha = isPresented && dimsBackground && layout.hasCollapsed ? 0.25 * expansion : 0

        for (slot, content) in slots where !content.container.isHidden {
            guard let entry = layout.contentEntries.first(where: { $0.content.first == slot }) else { continue }
            let size = content.container.bounds.size
            content.container.center = CGPoint(x: frame.width / 2, y: size.height / 2)
            content.container.alpha = opacities[entry.detent] ?? 0
            content.container.isUserInteractionEnabled = (opacities[entry.detent] ?? 0) > 0.5
        }
    }

    private func dimAlpha(top: CGFloat) -> CGFloat {
        guard dimsBackground, let layout, layout.hasCollapsed else { return 0 }
        return 0.25 * layout.expansion(top: top)
    }

    private func applyCurrent() {
        guard layout != nil, animatingTarget == nil, !isDragging else { return }
        apply(top: visualTop, fade: appliedFade)
    }

    private func stopAnimation() {
        driver.stop()
        animatingTarget = nil
    }

    // MARK: Snapping

    /// Springs the sheet's top edge from where it is to `target`, starting at
    /// `velocity` (points per second), and derives everything else from it each
    /// frame. Overshoot only moves the sheet along its path: past the collapsed bar
    /// the capsule slides a little lower and back, it never squashes.
    private func snap(to target: MantleDetent, velocity: CGFloat, fade: Set<MantleDetent>?) {
        guard let layout else { return }
        let from = visualTop
        stopAnimation()
        snapID += 1
        let id = snapID
        animatingTarget = target
        updateInteraction(restingAt: target)

        let targetTop = layout.top(for: target)
        let delta = Double(targetTop - from)
        // To or from the collapsed bar: Apple Music style. The morph spreads over
        // the whole trip, the spring is quick and nearly bounce-free, and only a
        // little of a hard flick's speed carries into the overshoot.
        let intoBar = layout.hasCollapsed && target == layout.entries.first?.detent
        let fromBar = layout.hasCollapsed && abs(from - layout.restTop) < 1 && !intoBar
        var morph: MorphSnap?
        if intoBar || fromBar {
            let farTop = intoBar ? from : targetTop
            morph = MorphSnap(farTop: farTop, farExpansion: layout.expansion(top: farTop))
        }
        let spring = intoBar || fromBar ? collapseSpring : spring
        let velocityLimit: CGFloat = intoBar || fromBar ? 2500 : 8000
        let initialVelocity = Double(min(max(velocity, -velocityLimit), velocityLimit))
        if target != layout.entries.last?.detent {
            // Snap points are measured from the top of the content, so leave the
            // largest detent with scrolled content back at its top.
            for scrollView in contentScrollViews() where scrollView.contentOffset.y > -scrollView.adjustedContentInset.top {
                scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: -scrollView.adjustedContentInset.top), animated: true)
            }
        }
        let duration = abs(delta) < 0.5 && abs(initialVelocity) < 1
            ? 0
            : spring.settlingDuration(target: delta, initialVelocity: initialVelocity, epsilon: 0.5)
        let start = CACurrentMediaTime()

        driver.start { [weak self] now in
            guard let self, snapID == id else { return false }
            let time = now - start
            guard time < duration else {
                apply(top: targetTop, fade: fade)
                animatingTarget = nil
                settle(at: target)
                return false
            }
            apply(top: from + CGFloat(spring.value(target: delta, initialVelocity: initialVelocity, time: time)), fade: fade, morph: morph)
            return true
        }
    }

    private func settle(at target: MantleDetent) {
        let changed = target != detent
        detent = target
        appliedFade = nil
        updateInteraction(restingAt: target)
        if changed { onDetentChange?(target) }
    }

    private func updateInteraction(restingAt target: MantleDetent) {
        guard let layout else { return }
        let collapsedRest = layout.hasCollapsed && target == layout.entries.first?.detent
        dimView.isUserInteractionEnabled = dimsBackground && !collapsedRest
        surface.updateAccessibility(collapsed: collapsedRest)
    }

    // MARK: Gestures

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === pan {
            let velocity = pan.velocity(in: view)
            return abs(velocity.y) > abs(velocity.x)
        }
        if gestureRecognizer === tap {
            return handlesTapToExpand && layout?.hasCollapsed == true && detent == layout?.entries.first?.detent && animatingTarget == nil
        }
        return true
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Controls inside the bar (play, next) take taps before the bar does.
        if gestureRecognizer === tap { return !(touch.view is UIControl) }
        return true
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // Cooperate with scroll views in the content: below the largest detent the
        // sheet moves instead of scrolling; at the largest it scrolls until the
        // content is at its top, then pulling down moves the sheet.
        // Run alongside every recogniser inside the sheet (SwiftUI's own touch
        // handling begins on touch-down and would otherwise stop the pan from
        // starting). Once the pan begins it cancels their touches, so a button a
        // drag starts on doesn't also fire.
        guard gestureRecognizer === pan, let otherView = other.view, otherView.isDescendant(of: surface) else { return false }
        if let scrollView = otherView as? UIScrollView, other === scrollView.panGestureRecognizer {
            trackedScrollView = scrollView
        }
        return true
    }

    /// Whether a drag moves the sheet or scrolls the content under the finger.
    private enum PanMode { case undecided, sheet, scroll }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        guard let layout else { return }
        let translation = pan.translation(in: view).y
        switch pan.state {
        case .began:
            // Find the scroll view under the finger directly: the simultaneous-
            // recognition callback that also reports it can arrive after this.
            trackedScrollView = scrollView(at: pan.location(in: surface)) ?? trackedScrollView
            panMode = .undecided
            panStartTranslation = translation
            lastTranslation = translation

        case .changed:
            let step = translation - lastTranslation
            lastTranslation = translation
            if panMode == .undecided {
                // Decide once the finger has moved, so the direction is known.
                guard abs(translation - panStartTranslation) >= 1 else { return }
                panMode = decidePanMode(pullingDown: translation > panStartTranslation, layout: layout)
                if panMode == .sheet { beginSheetDrag(at: translation) }
            }
            if panMode == .scroll {
                // Scroll until the content is at its top and the finger pulls down;
                // then the sheet takes over mid-gesture.
                guard let scrollView = trackedScrollView, step > 0,
                      scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top + 0.5
                else { return }
                panMode = .sheet
                beginSheetDrag(at: translation)
            }
            apply(top: layout.rubberBanded(dragStartTop + translation - dragStartTranslation), fade: nil)

        case .ended, .cancelled, .failed:
            defer {
                trackedScrollView = nil
                panMode = .undecided
            }
            guard panMode == .sheet else { return }
            isDragging = false
            trackedScrollView?.panGestureRecognizer.isEnabled = true
            release(top: visualTop, velocity: pan.state == .ended ? pan.velocity(in: view).y : 0, from: dragFrom)

        default:
            break
        }
    }

    /// Like UIKit sheets: below the largest detent the sheet moves; at the largest
    /// the content scrolls, unless it's at its top and the finger pulls down.
    private func decidePanMode(pullingDown: Bool, layout: MantleLayout<Slot>) -> PanMode {
        guard let scrollView = trackedScrollView else { return .sheet }
        let atLargest = (animatingTarget ?? detent) == layout.entries.last?.detent
        guard atLargest else { return .sheet }
        let atTop = scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top + 0.5
        return atTop && pullingDown ? .sheet : .scroll
    }

    private func beginSheetDrag(at translation: CGFloat) {
        dragFrom = animatingTarget ?? detent
        // A snap still settling hands over from exactly where it is.
        stopAnimation()
        isDragging = true
        dragStartTop = visualTop
        dragStartTranslation = translation
        if let scrollView = trackedScrollView {
            // Hand the gesture to the sheet: cancel the content's own scrolling and
            // hold it where it was (at most its top, if it was bouncing).
            scrollView.contentOffset.y = max(scrollView.contentOffset.y, -scrollView.adjustedContentInset.top)
            scrollView.panGestureRecognizer.isEnabled = false
        }
        updateInteraction(restingAt: dragFrom)
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        // Below the largest detent content doesn't scroll: its scroll gesture waits
        // for the sheet's pan to fail, so it never moves the content first.
        guard gestureRecognizer === pan, let layout,
              let scrollView = other.view as? UIScrollView, other === scrollView.panGestureRecognizer,
              scrollView.isDescendant(of: surface)
        else { return false }
        return (animatingTarget ?? detent) != layout.entries.last?.detent
    }

    /// Scroll views inside the detent content.
    private func contentScrollViews() -> [UIScrollView] {
        var result: [UIScrollView] = []
        func visit(_ view: UIView) {
            if let scrollView = view as? UIScrollView { result.append(scrollView) }
            view.subviews.forEach(visit)
        }
        visit(surface.contentView)
        return result
    }

    /// The innermost vertically scrollable scroll view under `point` (in the
    /// surface's coordinates), if any.
    private func scrollView(at point: CGPoint) -> UIScrollView? {
        var view = surface.hitTest(point, with: nil)
        while let current = view, current !== surface {
            if let scrollView = current as? UIScrollView, scrollView.isScrollEnabled,
               scrollView.contentSize.height + scrollView.adjustedContentInset.top + scrollView.adjustedContentInset.bottom > scrollView.bounds.height + 1 {
                return scrollView
            }
            view = current.superview
        }
        return nil
    }

    private func release(top: CGFloat, velocity: CGFloat, from start: MantleDetent) {
        guard let layout else { return }
        // Project where a flick would carry the sheet, then pick the closest detent.
        let projected = top + velocity * 0.18
        let nearest = layout.entries.min { abs($0.top - projected) < abs($1.top - projected) }!
        let target = layout.settle(from: start, proposed: nearest)
        snap(
            to: target.detent,
            velocity: velocity,
            // Jumping past intermediate detents: fade only between the two ends.
            fade: target.detent != nearest.detent ? [start, target.detent] : nil
        )
    }

    /// Expands the collapsed bar, if that's where it's resting.
    func handleTapToExpand() {
        guard let layout, layout.hasCollapsed, detent == layout.entries.first?.detent, animatingTarget == nil, !isDragging else { return }
        move(to: tapDestination.map(layout.resolve) ?? layout.entries.last!.detent)
    }

    @objc private func handleTap() { handleTapToExpand() }
    @objc private func handleDimTap() { collapse() }

    // MARK: Tab bar

    private func observeTabBar(_ controller: UITabBarController) {
        let bar = controller.tabBar
        let handler: @Sendable (Any, Any) -> Void = { [weak self] _, _ in
            DispatchQueue.main.async { self?.view.setNeedsLayout() }
        }
        tabBarObservations = [
            bar.layer.observe(\.position, changeHandler: handler),
            bar.layer.observe(\.bounds, changeHandler: handler),
            bar.observe(\.isHidden, changeHandler: handler),
        ]
    }

    private func updateContentInsets() {
        guard let tabBarController = hostTabBarController else { return }
        if isPresented, contentInsetMode == .automatic {
            insetter.apply(collapsedLayout.height + collapsedLayout.bottomInset, to: tabBarController)
        } else {
            insetter.remove()
        }
    }

    /// The bottom safe-area inset detent content should apply (hosting
    /// controllers that ignore UIKit's safe area need it passed in).
    var contentBottomInset: CGFloat { view.window?.safeAreaInsets.bottom ?? view.safeAreaInsets.bottom }

    /// Whether the mantle is resting at its largest detent.
    var isAtLargest: Bool { layout.map { detent == $0.entries.last?.detent } ?? false }

    /// Whether this mantle insets a tab bar controller's tabs.
    var insetsTabs: Bool { hostTabBarController != nil && contentInsetMode == .automatic }
}

/// Lets touches through everywhere except the mantle's own surfaces.
final class MantlePassthroughView: UIView {
    /// Checked in order, so list them front to back.
    var hitTargets: [UIView] = []

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for target in hitTargets where !target.isHidden && target.alpha > 0.01 && target.isUserInteractionEnabled {
            let local = convert(point, to: target)
            if target.point(inside: local, with: event), let hit = target.hitTest(local, with: event) {
                return hit
            }
        }
        return nil
    }
}
