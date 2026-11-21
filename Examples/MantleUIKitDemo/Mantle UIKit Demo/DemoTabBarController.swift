//
//  DemoTabBarController.swift
//  Mantle UIKit Demo
//
//  A UITabBarController with a `MantleViewController` installed above its tab
//  bar. The Settings tab switches between demos and changes the mantle live.
//

import Mantle
import UIKit

/// The ways the demo sets up the mantle.
enum MantleDemo: String, CaseIterable {
    case revealViews = "Reveal views"
    case fixedSnapPoints = "Fixed snap points"
    case perDetent = "Per detent"
    case tapTarget = "Tap target"

    var explanation: String {
        switch self {
        case .revealViews:
            "One scrolling player. Its header and artwork groups are `revealViews`: the mantle measures them after Auto Layout and snaps to show each group fully."
        case .fixedSnapPoints:
            "One player as `expandedContent`, with `.quarter` and `.half` as `snapPoints` that reveal its top."
        case .perDetent:
            "Different view controllers pinned to `.quarter`, `.half` and `.large` with `setContent(_:for:)`, cross-faded as the sheet moves."
        case .tapTarget:
            "No grabber: the bar is a tap target with interactive glass. It opens on tap and closes from code (the chevron calls `collapse()`)."
        }
    }

    /// The detents this demo declares, for "Move to".
    var detents: [MantleDetent] {
        switch self {
        case .revealViews: [.collapsed, .revealed("header"), .revealed("artwork"), .large]
        case .fixedSnapPoints: [.collapsed, .quarter, .half, .large]
        case .perDetent: [.collapsed, .quarter, .half, .large]
        case .tapTarget: [.collapsed, .large]
        }
    }
}

enum BackgroundChoice: String, CaseIterable {
    case glass = "Glass", blur = "Blur", opaque = "Opaque"

    var background: MantleBackground {
        switch self {
        case .glass: .glass
        case .blur: .blur(uiKit: .systemThinMaterial)
        case .opaque: .opaque
        }
    }
}

struct DemoSettings {
    var demo = MantleDemo.revealViews
    var collapsedBackground = BackgroundChoice.glass
    var expandedBackground = BackgroundChoice.opaque
    var dims = true
    var showsMantle = true
}

final class DemoTabBarController: UITabBarController {
    let player = PlayerModel()
    let mantle = MantleViewController()
    // `-demo revealViews|fixedSnapPoints|perDetent|tapTarget` and
    // `-detent collapsed|header|artwork|quarter|half|large` on launch.
    private var settings: DemoSettings = {
        var settings = DemoSettings()
        let demo = UserDefaults.standard.string(forKey: "demo")
        settings.demo = [MantleDemo.revealViews, .fixedSnapPoints, .perDetent, .tapTarget].first { "\($0)" == demo } ?? .revealViews
        return settings
    }()
    private var pinnedDetents: [MantleDetent] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        let library = UINavigationController(rootViewController: AlbumGridViewController(title: "Library"))
        library.tabBarItem = UITabBarItem(title: "Library", image: UIImage(systemName: "square.grid.2x2.fill"), tag: 0)
        let radio = UINavigationController(rootViewController: AlbumGridViewController(title: "Radio"))
        radio.tabBarItem = UITabBarItem(title: "Radio", image: UIImage(systemName: "dot.radiowaves.left.and.right"), tag: 1)
        let settingsScreen = SettingsViewController(
            settings: settings,
            onChange: { [weak self] in self?.apply($0) },
            onMove: { [weak self] in self?.mantle.move(to: $0) }
        )
        let settingsNavigation = UINavigationController(rootViewController: settingsScreen)
        settingsNavigation.tabBarItem = UITabBarItem(title: "Mantle", image: UIImage(systemName: "slider.horizontal.3"), tag: 2)
        viewControllers = [library, radio, settingsNavigation]

        // Above the tab bar; in `.automatic` inset mode every tab's bottom safe
        // area grows by the bar, so lists scroll clear of it.
        mantle.install(in: self)
        mantle.onDetentChange = { detent in print("Mantle settled at \(detent)") }
        configureContent(for: settings.demo)
        applyAppearance()
        if let detent = UserDefaults.standard.string(forKey: "detent") {
            let launch: MantleDetent? = switch detent {
            case "header", "artwork": .revealed(detent)
            case "quarter": .quarter
            case "half": .half
            case "large": .large
            default: nil
            }
            if let launch { mantle.move(to: launch, animated: false) }
        }
    }

    private func apply(_ new: DemoSettings) {
        let old = settings
        settings = new
        if new.demo != old.demo { configureContent(for: new.demo) }
        applyAppearance()
        if new.showsMantle != old.showsMantle { mantle.setPresented(new.showsMantle) }
    }

    private func applyAppearance() {
        mantle.background = settings.collapsedBackground.background
        mantle.expandedBackground = settings.expandedBackground.background
        mantle.dimsBackground = settings.dims
    }

    /// Sets the mantle up for one demo, from scratch.
    private func configureContent(for demo: MantleDemo) {
        mantle.move(to: .collapsed, animated: false)
        for detent in pinnedDetents { mantle.setContent(nil, for: detent) }
        pinnedDetents = []
        mantle.expandedContent = nil
        mantle.snapPoints = []
        mantle.revealViews = []
        mantle.expandedCollapseMode = .automatic
        mantle.showsGrabber = true

        pin(MiniPlayerViewController(player: player), to: .collapsed)
        let close: () -> Void = { [weak mantle] in mantle?.collapse() }

        switch demo {
        case .revealViews:
            let player = RevealPlayerViewController(player: player, onClose: close)
            mantle.expandedContent = player
            mantle.revealViews = player.revealViews
            // Dragging down from any reveal point (or .large) collapses fully.
            mantle.expandedCollapseMode = .target(.collapsed)

        case .fixedSnapPoints:
            mantle.expandedContent = FixedPlayerViewController(player: player, onClose: close)
            mantle.snapPoints = [.quarter, .half]
            mantle.expandedCollapseMode = .target(.collapsed)

        case .perDetent:
            pin(CompactPlayerViewController(player: player), to: .quarter)
            pin(QueueViewController(), to: .half)
            pin(FixedPlayerViewController(player: player, onClose: close), to: .large)

        case .tapTarget:
            mantle.expandedContent = FixedPlayerViewController(player: player, onClose: close)
            mantle.showsGrabber = false
        }
    }

    private func pin(_ controller: UIViewController, to detent: MantleDetent) {
        mantle.setContent(controller, for: detent)
        pinnedDetents.append(detent)
    }
}
