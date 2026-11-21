//
//  Components.swift
//  Mantle UIKit Demo
//
//  Small Auto Layout building blocks shared by the demo's screens.
//

import UIKit

/// Playback state shared by every player view.
@MainActor
final class PlayerModel {
    var isPlaying = false {
        didSet { observers.forEach { $0(isPlaying) } }
    }

    private var observers: [(Bool) -> Void] = []

    /// Calls `observer` now and whenever playback changes.
    func observe(_ observer: @escaping (Bool) -> Void) {
        observers.append(observer)
        observer(isPlaying)
    }

    func toggle() { isPlaying.toggle() }
}

/// A gradient square with a music note: stand-in album art.
final class ArtworkView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    init(size: CGFloat, cornerRadius: CGFloat, hue: CGFloat? = nil) {
        super.init(frame: .zero)
        let gradient = layer as! CAGradientLayer
        if let hue {
            gradient.colors = [UIColor(hue: hue, saturation: 0.55, brightness: 0.95, alpha: 1).cgColor,
                               UIColor(hue: hue, saturation: 0.7, brightness: 0.8, alpha: 1).cgColor]
            gradient.startPoint = CGPoint(x: 0.5, y: 0)
            gradient.endPoint = CGPoint(x: 0.5, y: 1)
        } else {
            gradient.colors = [UIColor.systemPink.cgColor, UIColor.systemOrange.cgColor, UIColor.systemPurple.cgColor]
            gradient.startPoint = CGPoint(x: 0, y: 0)
            gradient.endPoint = CGPoint(x: 1, y: 1)
        }
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        clipsToBounds = true
        translatesAutoresizingMaskIntoConstraints = false

        if hue == nil {
            let note = UIImageView(image: UIImage(systemName: "music.note"))
            note.tintColor = .white.withAlphaComponent(0.85)
            note.preferredSymbolConfiguration = .init(pointSize: size * 0.35)
            note.translatesAutoresizingMaskIntoConstraints = false
            addSubview(note)
            NSLayoutConstraint.activate([
                note.centerXAnchor.constraint(equalTo: centerXAnchor),
                note.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalTo: widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// A plain, tinted SF Symbol button.
func symbolButton(_ name: String, pointSize: CGFloat, action: @escaping () -> Void) -> UIButton {
    var configuration = UIButton.Configuration.plain()
    configuration.image = UIImage(systemName: name)
    configuration.preferredSymbolConfigurationForImage = .init(pointSize: pointSize, weight: .semibold)
    configuration.baseForegroundColor = .label
    configuration.contentInsets = .init(top: 6, leading: 6, bottom: 6, trailing: 6)
    let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
    button.setContentHuggingPriority(.required, for: .horizontal)
    return button
}

/// A play/pause button that follows the player.
func playButton(player: PlayerModel, pointSize: CGFloat) -> UIButton {
    let button = symbolButton("play.fill", pointSize: pointSize) { [weak player] in player?.toggle() }
    player.observe { [weak button] isPlaying in
        button?.configuration?.image = UIImage(systemName: isPlaying ? "pause.fill" : "play.fill")
    }
    return button
}

/// Title and artist, stacked.
func titleStack(titleStyle: UIFont.TextStyle, subtitleStyle: UIFont.TextStyle) -> UIStackView {
    let title = UILabel()
    title.text = "Midnight Static"
    title.font = .preferredFont(forTextStyle: titleStyle).bold()
    title.adjustsFontForContentSizeCategory = true
    let artist = UILabel()
    artist.text = "The Lanterns"
    artist.font = .preferredFont(forTextStyle: subtitleStyle)
    artist.adjustsFontForContentSizeCategory = true
    artist.textColor = .secondaryLabel
    let stack = UIStackView(arrangedSubviews: [title, artist])
    stack.axis = .vertical
    return stack
}

/// Artwork, titles, play and a collapse chevron: the expanded player's header row.
func headerRow(player: PlayerModel, onClose: @escaping () -> Void) -> UIStackView {
    let row = UIStackView(arrangedSubviews: [
        ArtworkView(size: 44, cornerRadius: 8),
        titleStack(titleStyle: .headline, subtitleStyle: .subheadline),
        UIView(),
        playButton(player: player, pointSize: 20),
        symbolButton("chevron.down", pointSize: 18, action: onClose),
    ])
    row.spacing = 14
    row.alignment = .center
    return row
}

/// A progress slider with elapsed and remaining times.
func scrubber() -> UIStackView {
    let slider = UISlider()
    slider.value = 0.32
    let elapsed = UILabel(), remaining = UILabel()
    elapsed.text = "1:12"
    remaining.text = "-2:31"
    for label in [elapsed, remaining] {
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabel
    }
    let times = UIStackView(arrangedSubviews: [elapsed, UIView(), remaining])
    let stack = UIStackView(arrangedSubviews: [slider, times])
    stack.axis = .vertical
    stack.spacing = 4
    return stack
}

/// Previous, play/pause, next.
func transportControls(player: PlayerModel, scale: CGFloat = 1) -> UIStackView {
    let stack = UIStackView(arrangedSubviews: [
        symbolButton("backward.fill", pointSize: 28 * scale) {},
        playButton(player: player, pointSize: 44 * scale),
        symbolButton("forward.fill", pointSize: 28 * scale) {},
    ])
    stack.spacing = 36 * scale
    stack.alignment = .center
    return stack
}

/// An "Up Next" list of `count` tracks.
func queueList(count: Int) -> UIStackView {
    let heading = UILabel()
    heading.text = "Up Next"
    heading.font = .preferredFont(forTextStyle: .title2).bold()
    var rows: [UIView] = [heading]
    for index in 1...count {
        let title = UILabel()
        title.text = "Track \(index)"
        title.font = .preferredFont(forTextStyle: .body)
        let artist = UILabel()
        artist.text = "The Lanterns"
        artist.font = .preferredFont(forTextStyle: .caption1)
        artist.textColor = .secondaryLabel
        let labels = UIStackView(arrangedSubviews: [title, artist])
        labels.axis = .vertical
        let row = UIStackView(arrangedSubviews: [ArtworkView(size: 40, cornerRadius: 6), labels])
        row.spacing = 12
        row.alignment = .center
        rows.append(row)
    }
    let stack = UIStackView(arrangedSubviews: rows)
    stack.axis = .vertical
    stack.spacing = 14
    stack.alignment = .leading
    return stack
}

extension UIFont {
    func bold() -> UIFont {
        fontDescriptor.withSymbolicTraits(.traitBold).map { UIFont(descriptor: $0, size: 0) } ?? self
    }
}

extension UIView {
    /// Pins `subview` to this view's edges, inset by `insets`.
    func addPinned(_ subview: UIView, insets: NSDirectionalEdgeInsets = .zero) {
        subview.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subview)
        NSLayoutConstraint.activate([
            subview.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            subview.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.leading),
            subview.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.trailing),
            subview.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom),
        ])
    }
}
