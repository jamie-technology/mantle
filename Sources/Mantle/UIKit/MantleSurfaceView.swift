import UIKit

/// The mantle's surface in UIKit: background (Liquid Glass, blur or colour, with
/// an optional cross-fade to an expanded background), a clipping content view and
/// the grabber.
///
/// Everything that changes as the sheet moves is a plain layer property (bounds,
/// corner radius, alpha), so Core Animation can interpolate it on the render
/// server, and nothing needs an offscreen pass: clipping uses the layer's own
/// continuous corners, and the shadow (only without glass) has an explicit path.
final class MantleSurfaceView: UIView {
    /// Holds the detent content; clips it to the surface's shape.
    let contentView = UIView()

    var onEscape: (() -> Void)?
    var onExpandAction: (() -> Void)?

    private var glassView: UIVisualEffectView?
    /// The collapsed background when it isn't glass.
    private var collapsedFill: UIView?
    private var collapsedFillFadesOut = false
    /// The expanded background when it isn't glass and differs from the collapsed one.
    private var expandedFill: UIView?
    private let grabber = UIView()
    private var hasShadow = false
    private var cornerRadius: CGFloat = 0
    private var grabberTop: CGFloat = 5

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.clipsToBounds = true
        contentView.layer.cornerCurve = .continuous
        addSubview(contentView)

        grabber.backgroundColor = .tertiaryLabel
        grabber.layer.cornerRadius = 2.5
        grabber.isUserInteractionEnabled = false
        grabber.isAccessibilityElement = false
        addSubview(grabber)

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowRadius = 14
        layer.shadowOffset = CGSize(width: 0, height: 6)
        layer.shadowOpacity = 0

        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Expand") { [weak self] _ in
                self?.onExpandAction?()
                return true
            },
        ]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Background

    func configure(background: MantleBackground, expanded: MantleBackground?, interactiveGlass: Bool) {
        [glassView, collapsedFill, expandedFill].forEach { $0?.removeFromSuperview() }
        glassView = nil
        collapsedFill = nil
        expandedFill = nil

        let collapsed = background.uiKit
        let expandedKind = (expanded ?? background).uiKit

        // Glass can't be faded, so if either end is glass it's the base layer and
        // the other background fades over it.
        let glass: (UIGlassEffect.Style, UIColor?)? = switch (collapsed, expandedKind) {
        case (.glass(let style, let tint), _), (_, .glass(let style, let tint)): (style, tint)
        default: nil
        }
        var layers: [UIView] = []
        if let (style, tint) = glass {
            let effect = UIGlassEffect(style: style)
            effect.tintColor = tint
            effect.isInteractive = interactiveGlass
            let view = UIVisualEffectView(effect: effect)
            glassView = view
            layers.append(view)
        }
        if !collapsed.isGlass {
            let fill = Self.makeFill(collapsed)
            collapsedFill = fill
            collapsedFillFadesOut = expandedKind.isGlass
            layers.append(fill)
        }
        if expanded != nil, !expandedKind.isGlass {
            let fill = Self.makeFill(expandedKind)
            expandedFill = fill
            layers.append(fill)
        }
        for (index, view) in layers.enumerated() {
            view.isUserInteractionEnabled = false
            view.layer.cornerCurve = .continuous
            view.clipsToBounds = true
            insertSubview(view, at: index)
        }
        hasShadow = glass == nil
        setNeedsLayout()
    }

    private static func makeFill(_ kind: MantleBackground.UIKitKind) -> UIView {
        switch kind {
        case .blur(let style): UIVisualEffectView(effect: UIBlurEffect(style: style))
        case .color(let color): { let view = UIView(); view.backgroundColor = color; return view }()
        case .glass: UIView()
        }
    }

    // MARK: Per-position state

    /// Everything that depends on the sheet's position, besides its frame.
    func apply(cornerRadius: CGFloat, expansion: CGFloat, showsGrabber: Bool, grabberTop: CGFloat) {
        self.cornerRadius = cornerRadius
        self.grabberTop = grabberTop
        for view in [contentView, glassView, collapsedFill, expandedFill].compactMap({ $0 }) {
            view.layer.cornerRadius = cornerRadius
        }
        glassView?.cornerConfiguration = .corners(radius: .fixed(Double(cornerRadius)))
        collapsedFill?.alpha = collapsedFillFadesOut ? 1 - expansion : 1
        expandedFill?.alpha = expansion
        layer.shadowOpacity = hasShadow ? Float(0.18 * (1 - expansion)) : 0
        grabber.alpha = showsGrabber ? 1 : 0
        layoutBackgrounds()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutBackgrounds()
    }

    private func layoutBackgrounds() {
        for view in [contentView, glassView, collapsedFill, expandedFill].compactMap({ $0 }) where view.frame != bounds {
            view.frame = bounds
        }
        grabber.frame = CGRect(x: (bounds.width - 36) / 2, y: grabberTop, width: 36, height: 5)
        if hasShadow {
            layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).cgPath
        }
    }

    // MARK: Accessibility

    func updateAccessibility(collapsed: Bool) {
        // Collapsed, the bar reads as one button that expands it.
        shouldGroupAccessibilityChildren = collapsed
        accessibilityTraits = collapsed ? .button : []
    }

    override func accessibilityPerformEscape() -> Bool {
        onEscape?()
        return true
    }
}

extension MantleBackground.UIKitKind {
    var isGlass: Bool {
        if case .glass = self { true } else { false }
    }
}
