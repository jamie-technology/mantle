//
//  AlbumGridViewController.swift
//  Mantle UIKit Demo
//
//  A compositional-layout grid that scrolls under the mantle. The mantle adds
//  the collapsed bar to this tab's bottom safe area, so the last row can scroll
//  clear of it.
//

import UIKit

final class AlbumGridViewController: UICollectionViewController {
    init(title: String) {
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(0.5), heightDimension: .estimated(220)))
        item.contentInsets = .init(top: 0, leading: 8, bottom: 0, trailing: 8)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(220)), subitems: [item, item])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 20
        section.contentInsets = .init(top: 8, leading: 8, bottom: 16, trailing: 8)
        super.init(collectionViewLayout: UICollectionViewCompositionalLayout(section: section))
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private let registration = UICollectionView.CellRegistration<AlbumCell, Int> { cell, _, index in
        cell.configure(index: index)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.navigationBar.prefersLargeTitles = true
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { 24 }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: indexPath.item)
    }
}

private final class AlbumCell: UICollectionViewCell {
    private let artworkContainer = UIView()
    private let title = UILabel()
    private let artist = UILabel()
    private var artwork: ArtworkView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        title.font = .preferredFont(forTextStyle: .subheadline).bold()
        artist.font = .preferredFont(forTextStyle: .caption1)
        artist.textColor = .secondaryLabel
        artist.text = "Artist"
        artworkContainer.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView(arrangedSubviews: [artworkContainer, title, artist])
        stack.axis = .vertical
        stack.spacing = 4
        stack.setCustomSpacing(8, after: artworkContainer)
        contentView.addPinned(stack)
        artworkContainer.heightAnchor.constraint(equalTo: artworkContainer.widthAnchor).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(index: Int) {
        title.text = "Album \(index + 1)"
        artwork?.removeFromSuperview()
        let artwork = ArtworkView(size: 0, cornerRadius: 10, hue: CGFloat(index) / 24)
        // Fill the square container instead of a fixed size.
        artwork.constraints.forEach { $0.isActive = false }
        artworkContainer.addPinned(artwork)
        self.artwork = artwork
    }
}
