import SwiftUI
import UIKit

/// The SwiftUI `.mantle` API on the UIKit engine.
///
/// SwiftUI resolves the builder's detents (static metadata, recomputed only when
/// the content changes) and a `MantleViewController` does everything that moves.
/// Each detent's content is hosted in its own `UIHostingController`, which gets
/// the surrounding environment, so the content renders exactly as it would in
/// place. Nothing here runs per frame.
struct MantleUIKitHost<Detents: View>: View {
    @Binding var selection: MantleDetent
    let isPresented: Bool
    let detents: Detents

    @Environment(\.self) private var environment
    @Environment(\.mantleConfiguration) private var configuration

    var body: some View {
        Group(subviews: detents) { subviews in
            MantleUIKitRepresentable(
                selection: $selection,
                isPresented: isPresented,
                detents: detents,
                metadata: .init(subviews),
                environment: environment,
                configuration: configuration
            )
        }
    }
}

/// What the UIKit engine needs to know about the builder's content.
struct MantleBuilderMetadata {
    struct Entry {
        let detent: MantleDetent
        let hasContent: Bool
        let collapseMode: MantleCollapseMode
    }

    var entries: [Entry] = []
    var hasExpandedContent = false
    var expandedCollapseMode: MantleCollapseMode = .automatic

    init(_ subviews: SubviewsCollection) {
        var seen = Set<MantleDetent>()
        for subview in subviews {
            let values = subview.containerValues
            guard let detent = values.mantleDetent else {
                hasExpandedContent = true
                if expandedCollapseMode == .automatic { expandedCollapseMode = values.mantleCollapseMode }
                continue
            }
            guard seen.insert(detent).inserted else { continue }
            entries.append(.init(detent: detent, hasContent: values.mantleDetentHasContent, collapseMode: values.mantleCollapseMode))
        }
    }
}

private struct MantleUIKitRepresentable<Detents: View>: UIViewControllerRepresentable {
    @Binding var selection: MantleDetent
    let isPresented: Bool
    let detents: Detents
    let metadata: MantleBuilderMetadata
    let environment: EnvironmentValues
    let configuration: MantleConfiguration

    func makeUIViewController(context: Context) -> MantleBridgeController {
        MantleBridgeController()
    }

    func updateUIViewController(_ bridge: MantleBridgeController, context: Context) {
        bridge.update(
            selection: $selection,
            isPresented: isPresented,
            detents: detents,
            metadata: metadata,
            environment: environment,
            configuration: configuration
        )
    }

    static func dismantleUIViewController(_ bridge: MantleBridgeController, coordinator: ()) {
        bridge.mantle.uninstall()
    }
}

/// Owns the `MantleViewController` and its hosted SwiftUI content, and installs it
/// in the `TabView`'s tab bar controller, outside SwiftUI's own view tree, so
/// touches on the mantle never hit-test the SwiftUI hierarchy. Without a tab bar
/// controller it installs over its own (transparent, pass-through) view.
final class MantleBridgeController: UIViewController {
    let mantle = MantleViewController()
    private var hosts: [MantleViewController.Slot: UIHostingController<AnyView>] = [:]
    private var selection: Binding<MantleDetent>?
    private var isPresented = true

    override func loadView() {
        view = MantlePassthroughView()
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        installIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        installIfNeeded()
    }

    private func installIfNeeded() {
        guard mantle.parent == nil, let window = view.window else { return }
        if let bar = MantleTabBarLookup.tabBar(in: window, visibleOnly: false),
           let tabBarController = MantleTabBarLookup.tabBarController(of: bar) {
            mantle.install(in: tabBarController)
        } else {
            mantle.install(in: self)
        }
        mantle.setPresented(isPresented, animated: false)
        if let selection { mantle.move(to: selection.wrappedValue, animated: false) }
    }

    func update<Detents: View>(
        selection: Binding<MantleDetent>,
        isPresented: Bool,
        detents: Detents,
        metadata: MantleBuilderMetadata,
        environment: EnvironmentValues,
        configuration: MantleConfiguration
    ) {
        self.selection = selection
        self.isPresented = isPresented

        // Configuration.
        mantle.handlesTapToExpand = false
        mantle.background = configuration.background
        mantle.expandedBackground = configuration.expandedBackground
        mantle.showsGrabber = configuration.grabber != .hidden
        mantle.dimsBackground = configuration.dimsBackground
        mantle.collapsedLayout = configuration.collapsedLayout
        mantle.cornerRadius = configuration.cornerRadius
        mantle.tapDestination = configuration.tapDestination
        mantle.spring = configuration.spring
        mantle.collapseSpring = configuration.collapseSpring
        mantle.contentInsetMode = configuration.contentInsetMode
        mantle.onDetentChange = { selection.wrappedValue = $0 }

        // Detents.
        mantle.snapPoints = metadata.entries.filter { !$0.hasContent }.map(\.detent)
        for entry in metadata.entries {
            mantle.setCollapseMode(entry.collapseMode, for: entry.detent)
        }
        mantle.expandedCollapseMode = metadata.expandedCollapseMode

        // Content: one hosting controller per slot.
        var wanted = metadata.entries.filter(\.hasContent).map { MantleViewController.Slot.detent($0.detent) }
        if metadata.hasExpandedContent { wanted.append(.expanded) }
        for slot in hosts.keys where !wanted.contains(slot) {
            hosts[slot] = nil
            setContent(nil, for: slot)
        }
        let proxy = MantleProxy(
            detent: mantle.detent,
            detents: mantle.detents,
            move: { [weak mantle] in mantle?.move(to: $0) }
        )
        for slot in wanted {
            let root = AnyView(slotView(slot, detents: detents, proxy: proxy, environment: environment))
            if let host = hosts[slot] {
                host.rootView = root
            } else {
                let host = UIHostingController(rootView: root)
                // The mantle lays the content out at fixed sizes and applies the
                // safe area itself, so moving the sheet never re-lays it out.
                host.safeAreaRegions = []
                host.sizingOptions = []
                host.view.backgroundColor = .clear
                hosts[slot] = host
                setContent(host, for: slot)
            }
        }

        // State.
        installIfNeeded()
        mantle.setPresented(isPresented, animated: true)
        if mantle.layout != nil, mantle.layout?.resolve(selection.wrappedValue) != mantle.detent {
            mantle.move(to: selection.wrappedValue)
        }
    }

    private func setContent(_ controller: UIViewController?, for slot: MantleViewController.Slot) {
        switch slot {
        case .detent(let detent): mantle.setContent(controller, for: detent)
        case .expanded: mantle.expandedContent = controller
        }
    }

    @ViewBuilder
    private func slotView<Detents: View>(_ slot: MantleViewController.Slot, detents: Detents, proxy: MantleProxy, environment: EnvironmentValues) -> some View {
        MantleSlotView(detents: detents, slot: slot)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(.rect)
            // The collapsed bar expands on tap; buttons inside it take precedence.
            .onTapGesture { [weak mantle] in
                if slot == .detent(.collapsed) { mantle?.handleTapToExpand() }
            }
            .coordinateSpace(.named(MantleRevealKey.space))
            .onPreferenceChange(MantleRevealKey.self) { [weak mantle] markers in
                guard slot == .expanded, let mantle else { return }
                // At the largest detent the content may be scrolled, which moves the
                // markers; keep the snap points from before scrolling started.
                if mantle.isAtLargest, !mantle.revealMarkers.isEmpty { return }
                mantle.revealMarkers = markers
            }
            .safeAreaPadding(.bottom, slot == .detent(.collapsed) ? 0 : mantle.contentBottomInset)
            .environment(\.mantle, proxy)
            .environment(\.self, environment)
    }
}

/// Renders just one slot's content from the full builder.
private struct MantleSlotView<Detents: View>: View {
    let detents: Detents
    let slot: MantleViewController.Slot

    var body: some View {
        Group(subviews: detents) { subviews in
            switch slot {
            case .detent(let detent):
                if let subview = subviews.first(where: {
                    $0.containerValues.mantleDetent == detent && $0.containerValues.mantleDetentHasContent
                }) {
                    subview
                }
            case .expanded:
                VStack(spacing: 0) {
                    ForEach(subviews.filter { $0.containerValues.mantleDetent == nil }) { $0 }
                }
            }
        }
    }
}
