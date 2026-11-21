//
//  UIKitAPIDemo.swift
//  Mantle Demo
//
//  The UIKit API: a plain UITabBarController with a `MantleViewController`
//  installed above its tab bar, no SwiftUI `.mantle` involved. The collapsed bar
//  is pure UIKit; the expanded player is SwiftUI in a UIHostingController, given
//  the mantle's proxy so its close button works.
//

import SwiftUI
import UIKit
import Mantle

struct UIKitAPIDemo: UIViewControllerRepresentable {
    @Binding var engine: DemoEngine

    func makeUIViewController(context: Context) -> UITabBarController {
        let tabs = UITabBarController()
        let home = UINavigationController(rootViewController: UIHostingController(rootView: AlbumGrid(title: "Home")))
        home.tabBarItem = UITabBarItem(title: "Home", image: UIImage(systemName: "house.fill"), tag: 0)
        let settings = UIHostingController(rootView: EngineSettings(engine: $engine))
        settings.tabBarItem = UITabBarItem(title: "Engine", image: UIImage(systemName: "slider.horizontal.3"), tag: 1)
        tabs.viewControllers = [home, settings]

        let mantle = MantleViewController()
        mantle.background = .glass
        mantle.expandedBackground = .opaque
        mantle.setContent(MiniPlayerViewController(onPlay: {}), for: .collapsed)
        mantle.snapPoints = [.half]
        mantle.expandedContent = UIHostingController(rootView: NowPlayingHost(mantle: mantle))
        mantle.expandedCollapseMode = .target(.collapsed)
        mantle.install(in: tabs)
        context.coordinator.mantle = mantle
        return tabs
    }

    func updateUIViewController(_ tabs: UITabBarController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var mantle: MantleViewController?
    }
}

/// The collapsed bar, in plain UIKit.
private final class MiniPlayerViewController: UIViewController {
    let onPlay: () -> Void

    init(onPlay: @escaping () -> Void) {
        self.onPlay = onPlay
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let artwork = UIView()
        artwork.backgroundColor = .systemPink
        artwork.layer.cornerRadius = 8
        artwork.layer.cornerCurve = .continuous
        artwork.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = "Midnight Static"
        title.font = .preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
        let artist = UILabel()
        artist.text = "The Lanterns"
        artist.font = .preferredFont(forTextStyle: .caption1)
        artist.textColor = .secondaryLabel
        let labels = UIStackView(arrangedSubviews: [title, artist])
        labels.axis = .vertical

        let play = UIButton(configuration: .plain())
        play.setImage(UIImage(systemName: "play.fill"), for: .normal)
        play.tintColor = .label
        play.addAction(UIAction { [weak self] _ in self?.onPlay() }, for: .primaryActionTriggered)

        let row = UIStackView(arrangedSubviews: [artwork, labels, UIView(), play])
        row.spacing = 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(row)
        NSLayoutConstraint.activate([
            artwork.widthAnchor.constraint(equalToConstant: 40),
            artwork.heightAnchor.constraint(equalToConstant: 40),
            row.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            row.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        UIFont.systemFont(ofSize: pointSize, weight: weight)
    }
}

/// The expanded player, in SwiftUI, with the mantle's proxy in its environment.
private struct NowPlayingHost: View {
    let mantle: MantleViewController
    @State private var isPlaying = false

    var body: some View {
        NowPlaying(isPlaying: $isPlaying)
            .environment(\.mantle, mantle.proxy)
    }
}

private struct EngineSettings: View {
    @Binding var engine: DemoEngine

    var body: some View {
        Form {
            Picker("Engine", selection: $engine) {
                ForEach(DemoEngine.allCases) { Text($0.title) }
            }
        }
    }
}
