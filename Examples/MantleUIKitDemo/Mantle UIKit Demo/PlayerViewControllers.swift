//
//  PlayerViewControllers.swift
//  Mantle UIKit Demo
//
//  The content shown in the mantle, all built with Auto Layout. The mantle sizes
//  each view controller's view once, to its detent, so these constraints are
//  solved once, not while the sheet moves.
//

import Mantle
import UIKit

/// The collapsed bar: artwork, titles, play and next.
final class MiniPlayerViewController: UIViewController {
    private let player: PlayerModel

    init(player: PlayerModel) {
        self.player = player
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let row = UIStackView(arrangedSubviews: [
            ArtworkView(size: 40, cornerRadius: 8),
            titleStack(titleStyle: .subheadline, subtitleStyle: .caption1),
            UIView(),
            playButton(player: player, pointSize: 18),
            symbolButton("forward.fill", pointSize: 18) {},
        ])
        row.spacing = 10
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            row.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}

/// One scrolling player whose header and artwork groups are reveal views: the
/// mantle measures them after Auto Layout and snaps to show each group fully.
/// Their positions are measured in the scroll view's content, so scrolling the
/// queue never moves the snap points.
final class RevealPlayerViewController: UIViewController {
    private let player: PlayerModel
    private let onClose: () -> Void
    private let scrollView = UIScrollView()
    private(set) lazy var headerGroup = UIStackView(arrangedSubviews: [headerRow(player: player, onClose: onClose), scrubber()])
    private(set) lazy var artworkGroup = UIStackView(arrangedSubviews: [ArtworkView(size: 280, cornerRadius: 16), transportControls(player: player)])

    /// Hand these to `MantleViewController.revealViews`.
    var revealViews: [MantleRevealView] {
        loadViewIfNeeded()
        return [
            MantleRevealView(id: "header", view: headerGroup),
            MantleRevealView(id: "artwork", view: artworkGroup),
        ]
    }

    init(player: PlayerModel, onClose: @escaping () -> Void) {
        self.player = player
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        headerGroup.axis = .vertical
        headerGroup.spacing = 16
        artworkGroup.axis = .vertical
        artworkGroup.spacing = 28
        artworkGroup.alignment = .center

        let content = UIStackView(arrangedSubviews: [headerGroup, artworkGroup, queueList(count: 20)])
        content.axis = .vertical
        content.spacing = 24
        content.alignment = .fill
        content.translatesAutoresizingMaskIntoConstraints = false

        // Under the home indicator, like a system sheet: the mantle gives the
        // content the bottom safe area, and the scroll view insets its content.
        scrollView.contentInsetAdjustmentBehavior = .always
        view.addPinned(scrollView)
        scrollView.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            content.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 28),
            content.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -28),
        ])
    }
}

/// The full player, top-aligned and not scrolling: used where smaller detents
/// reveal its top, or as a large detent's own content.
final class FixedPlayerViewController: UIViewController {
    private let player: PlayerModel
    private let onClose: () -> Void

    init(player: PlayerModel, onClose: @escaping () -> Void) {
        self.player = player
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let artwork = UIStackView(arrangedSubviews: [ArtworkView(size: 280, cornerRadius: 16), transportControls(player: player)])
        artwork.axis = .vertical
        artwork.spacing = 28
        artwork.alignment = .center
        let stack = UIStackView(arrangedSubviews: [headerRow(player: player, onClose: onClose), scrubber(), artwork])
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
        ])
    }
}

/// A compact player for a small pinned detent.
final class CompactPlayerViewController: UIViewController {
    private let player: PlayerModel

    init(player: PlayerModel) {
        self.player = player
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let header = UIStackView(arrangedSubviews: [ArtworkView(size: 52, cornerRadius: 10), titleStack(titleStyle: .headline, subtitleStyle: .body), UIView()])
        header.spacing = 14
        header.alignment = .center
        let controls = transportControls(player: player, scale: 0.7)
        let centred = UIStackView(arrangedSubviews: [controls])
        centred.alignment = .center
        centred.axis = .vertical
        let stack = UIStackView(arrangedSubviews: [header, scrubber(), centred])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
    }
}

/// The queue, for a medium pinned detent.
final class QueueViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let list = queueList(count: 6)
        list.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(list)
        NSLayoutConstraint.activate([
            list.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),
            list.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            list.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }
}
