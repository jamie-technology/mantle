import SwiftUI
import UIKit

/// Bridges the mantle to the `TabView`'s UIKit tab bar controller:
/// - reports the top of the visible tab bar, so the collapsed mantle can sit
///   just above it;
/// - adds `contentInset` to the bottom safe area of every tab, the way a tab view
///   bottom accessory does, so scroll views can scroll clear of the collapsed bar.
///
/// SwiftUI safe-area modifiers on a `TabView` don't reach its tabs (each tab is
/// hosted in its own view controller), so the tab inset has to be applied here.
struct TabBarReader: UIViewRepresentable {
    struct Measurement: Equatable {
        /// Top of the visible tab bar in window coordinates.
        var top: CGFloat?
        /// Whether a tab bar controller was found and its tabs are being inset.
        var insetsTabs: Bool
    }

    var contentInset: CGFloat
    var onChange: (Measurement) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.contentInset = contentInset
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.contentInset = contentInset
        view.onChange = onChange
        view.setNeedsLayout()
    }

    static func dismantleUIView(_ view: ProbeView, coordinator: ()) {
        view.removeTabInsets()
    }

    final class ProbeView: UIView {
        var contentInset: CGFloat = 0
        var onChange: ((Measurement) -> Void)?
        private var last: Measurement?
        private weak var observedBar: UITabBar?
        private weak var tabBarController: UITabBarController?
        private var observations: [NSKeyValueObservation] = []
        private let insetter = MantleTabInsetter()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            measure()
            // The tab bar may lay out after us on first appearance.
            DispatchQueue.main.async { [weak self] in self?.measure() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            measure()
        }

        private func measure() {
            guard let window else { return }
            let visibleBar = MantleTabBarLookup.tabBar(in: window, visibleOnly: true)
            if visibleBar !== observedBar { observe(visibleBar) }

            // Keep insetting the tabs while the tab bar is hidden (e.g. on a pushed
            // screen): the collapsed bar is still there.
            if tabBarController == nil || tabBarController?.view.window == nil {
                let bar = visibleBar ?? MantleTabBarLookup.tabBar(in: window, visibleOnly: false)
                let controller = bar.flatMap(MantleTabBarLookup.tabBarController(of:))
                if controller !== tabBarController { removeTabInsets() }
                tabBarController = controller
            }
            if let tabBarController { insetter.apply(contentInset, to: tabBarController) }

            let measurement = Measurement(
                top: visibleBar.map { $0.convert($0.bounds, to: window).minY },
                insetsTabs: tabBarController != nil
            )
            guard measurement != last else { return }
            last = measurement
            onChange?(measurement)
        }

        func removeTabInsets() {
            insetter.remove()
            tabBarController = nil
        }

        private func observe(_ bar: UITabBar?) {
            observedBar = bar
            observations = []
            guard let bar else { return }
            let handler: @Sendable (Any, Any) -> Void = { [weak self] _, _ in
                DispatchQueue.main.async { self?.measure() }
            }
            observations = [
                bar.layer.observe(\.position, changeHandler: handler),
                bar.layer.observe(\.bounds, changeHandler: handler),
                bar.observe(\.isHidden, changeHandler: handler),
            ]
        }
    }
}

/// Adds an inset to the bottom safe area of every tab of a tab bar controller,
/// the way a tab view bottom accessory does. Each tab's own inset is kept, added
/// to, and restored exactly by `remove()`.
@MainActor
final class MantleTabInsetter {
    private var originalInsets: [ObjectIdentifier: (controller: Weak<UIViewController>, bottom: CGFloat)] = [:]

    func apply(_ inset: CGFloat, to controller: UITabBarController) {
        for child in controller.viewControllers ?? controller.children {
            let id = ObjectIdentifier(child)
            let original = originalInsets[id]?.bottom ?? child.additionalSafeAreaInsets.bottom
            originalInsets[id] = (Weak(child), original)
            let target = original + inset
            if child.additionalSafeAreaInsets.bottom != target {
                child.additionalSafeAreaInsets.bottom = target
            }
        }
    }

    func remove() {
        for (_, entry) in originalInsets {
            entry.controller.value?.additionalSafeAreaInsets.bottom = entry.bottom
        }
        originalInsets = [:]
    }
}

@MainActor
enum MantleTabBarLookup {
    static func tabBarController(of bar: UITabBar) -> UITabBarController? {
        var responder: UIResponder? = bar
        while let current = responder {
            if let controller = current as? UITabBarController { return controller }
            responder = current.next
        }
        return nil
    }

    static func tabBar(in view: UIView, visibleOnly: Bool) -> UITabBar? {
        if let bar = view as? UITabBar {
            guard visibleOnly else { return bar }
            return bar.isHidden || bar.alpha < 0.01 || bar.window == nil ? nil : bar
        }
        for subview in view.subviews where !(visibleOnly && subview.isHidden) {
            if let bar = tabBar(in: subview, visibleOnly: visibleOnly) { return bar }
        }
        return nil
    }
}

struct Weak<T: AnyObject> {
    weak var value: T?
    init(_ value: T) { self.value = value }
}
