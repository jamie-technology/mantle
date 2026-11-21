//
//  ContentView.swift
//  Mantle Demo
//
//  Created by Jamie Bishop on 20/11/2026.
//

import SwiftUI
import Mantle

enum BackgroundChoice: String, CaseIterable, Identifiable {
    case glass = "Glass", blur = "Blur", opaque = "Opaque"
    var id: Self { self }

    var background: MantleBackground {
        switch self {
        case .glass: .glass
        case .blur: .blur
        case .opaque: .opaque
        }
    }
}

enum DemoEngine: String, CaseIterable, Identifiable {
    case uiKit = "uikit", swiftUI = "swiftui", uiKitAPI = "uikitapi"
    var id: Self { self }
    var title: String {
        switch self {
        case .uiKit: "UIKit"
        case .swiftUI: "SwiftUI"
        case .uiKitAPI: "UIKit API"
        }
    }
}

struct ContentView: View {
    // `-detent half` / `-detent artwork` etc. on launch, handy for screenshots.
    @State private var detent: MantleDetent = Self.launchDetent

    private static var launchDetent: MantleDetent {
        switch UserDefaults.standard.string(forKey: "detent") {
        case "quarter": .quarter
        case "half": .half
        case "large": .large
        case "header": .revealed("header")
        case "artwork": .revealed("artwork")
        default: .collapsed
        }
    }
    @State private var collapsedBackground: BackgroundChoice = .glass
    @State private var expandedBackground: BackgroundChoice = .opaque
    @State private var showsGrabber = true
    // `-hideMantle YES` on launch starts with the mantle hidden.
    @State private var showsMantle = !UserDefaults.standard.bool(forKey: "hideMantle")
    @State private var dims = true
    /// Opts the middle snap point out of the inherited "collapse" target.
    @State private var middleStepsDown = false
    @State private var isPlaying = false
    @State private var mode = Mode.reveal
    // `-engine swiftui|uikit|uikitapi` on launch picks the engine.
    @State private var engine = DemoEngine(rawValue: UserDefaults.standard.string(forKey: "engine") ?? "") ?? .uiKit

    enum Mode: String, CaseIterable, Identifiable {
        case reveal = "Reveal markers"
        case fixed = "Fixed snap points"
        case perDetent = "Per detent"
        var id: Self { self }

        /// The detents this mode declares, for "Move to".
        var detents: [MantleDetent] {
            switch self {
            case .reveal: [.collapsed, .revealed("header"), .revealed("artwork"), .large]
            case .fixed, .perDetent: [.collapsed, .quarter, .half, .large]
            }
        }
    }

    var body: some View {
        if engine == .uiKitAPI {
            // The same idea built directly on `MantleViewController`, no SwiftUI `.mantle`.
            UIKitAPIDemo(engine: $engine)
                .ignoresSafeArea()
        } else {
            swiftUIMantle
        }
    }

    private var swiftUIMantle: some View {
        // One `.mantle` call with the mode switch inside the builder, so changing
        // modes keeps the same TabView (and its selected tab).
        tabs.mantle(isPresented: $showsMantle, selection: $detent) {
            Detent(.collapsed) { MiniPlayer(isPlaying: $isPlaying) }
            switch mode {
            case .reveal:
                // One scrolling sheet; each `Detent { }` group is a content-sized snap point.
                // Dragging down from any snap point collapses (inherited from this
                // target), except the artwork marker when it opts out with `.nearest`.
                RevealPlayer(isPlaying: $isPlaying, artworkCollapseMode: middleCollapseMode)
                    .collapseTarget(.collapsed)
            case .fixed:
                // Same expanded content at every detent, progressively revealed.
                // (Equivalent to `.mantle(selection:detents:collapsed:expanded:)`.)
                Detent(.quarter)
                Detent(.half)
                    .mantleCollapseMode(middleCollapseMode)
                NowPlaying(isPlaying: $isPlaying)
                    .collapseTarget(.collapsed)
            case .perDetent:
                // Different content pinned to each detent, cross-faded.
                Detent(.quarter) { CompactPlayer(isPlaying: $isPlaying) }
                Detent(.half) { QueueView() }
                Detent(.large) { NowPlaying(isPlaying: $isPlaying) }
            }
        }
        .mantleBackground(collapsedBackground.background, expanded: expandedBackground.background)
        .mantleGrabber(showsGrabber ? .visible : .hidden)
        .mantleDimming(dims)
        .mantleEngine(engine == .swiftUI ? .swiftUI : .uiKit)
    }

    private var middleCollapseMode: MantleCollapseMode {
        middleStepsDown ? .nearest : .automatic
    }

    private var tabs: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") {
                NavigationStack { AlbumGrid(title: "Home") }
            }
            Tab("New", systemImage: "square.grid.2x2.fill") {
                NavigationStack { AlbumGrid(title: "New") }
            }
            Tab("Mantle", systemImage: "slider.horizontal.3") {
                NavigationStack {
                    Form {
                        Section {
                            Picker("Engine", selection: $engine) {
                                ForEach(DemoEngine.allCases) { Text($0.title) }
                            }
                        } header: {
                            Text("Engine")
                        } footer: {
                            Text("UIKit: the SwiftUI API, animated by UIKit on the render server at the display's full refresh rate. SwiftUI: SwiftUI views and animations. UIKit API: `MantleViewController` used directly.")
                        }
                        Section("Content") {
                            Picker("Mode", selection: $mode) {
                                ForEach(Mode.allCases) { Text($0.rawValue) }
                            }
                        }
                        Section("Background") {
                            Picker("Collapsed", selection: $collapsedBackground) {
                                ForEach(BackgroundChoice.allCases) { Text($0.rawValue) }
                            }
                            Picker("Expanded", selection: $expandedBackground) {
                                ForEach(BackgroundChoice.allCases) { Text($0.rawValue) }
                            }
                        }
                        Section {
                            Toggle("Show mantle", isOn: $showsMantle)
                            Toggle("Grabber (draggable sheet)", isOn: $showsGrabber)
                            Toggle("Dim background", isOn: $dims)
                        } footer: {
                            Text("Without a grabber the mantle is a tap target: tap the bar to open it, use the chevron to close.")
                        }
                        Section {
                            Toggle("Middle snap point steps down", isOn: $middleStepsDown)
                        } header: {
                            Text("Dismissing")
                        } footer: {
                            Text("Dragging the player down collapses it from every snap point (`.collapseTarget(.collapsed)`, inherited by snap points). Turn this on to opt the middle snap point (the artwork marker, or .half) out with `.mantleCollapseMode(.nearest)`, so dragging down from there steps to the next smaller snap point instead. Applies to Reveal markers and Fixed snap points.")
                        }
                        Section("Move to") {
                            ForEach(mode.detents, id: \.self) { d in
                                Button(d.description) { detent = d }
                            }
                        }
                    }
                    .navigationTitle("Mantle")
                }
            }
            Tab("Library", systemImage: "music.note.list") {
                NavigationStack { AlbumGrid(title: "Library") }
            }
            Tab(role: .search) {
                NavigationStack { AlbumGrid(title: "Search") }
            }
        }
    }
}

// MARK: - Detent content

struct Artwork: View {
    var size: CGFloat
    var radius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(LinearGradient(colors: [.pink, .orange, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay { Image(systemName: "music.note").font(.system(size: size * 0.35)).foregroundStyle(.white.opacity(0.8)) }
            .frame(width: size, height: size)
    }
}

struct MiniPlayer: View {
    @Binding var isPlaying: Bool

    var body: some View {
        HStack(spacing: 12) {
            Artwork(size: 40, radius: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text("Midnight Static").font(.subheadline.weight(.semibold))
                Text("The Lanterns").font(.caption).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer()
            Button(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill") { isPlaying.toggle() }
                .contentTransition(.symbolEffect(.replace))
            Button("Next", systemImage: "forward.fill") {}
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .buttonStyle(.plain)
        .padding(.leading, 8)
        .padding(.trailing, 20)
        .frame(maxHeight: .infinity)
    }
}

struct TransportControls: View {
    @Binding var isPlaying: Bool
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 44 * scale) {
            Button("Previous", systemImage: "backward.fill") {}
            Button(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill") { isPlaying.toggle() }
                .font(.system(size: 44 * scale))
                .contentTransition(.symbolEffect(.replace))
            Button("Next", systemImage: "forward.fill") {}
        }
        .labelStyle(.iconOnly)
        .font(.system(size: 28 * scale))
        .buttonStyle(.plain)
    }
}

struct Scrubber: View {
    @State private var progress = 0.32

    var body: some View {
        VStack(spacing: 4) {
            Slider(value: $progress)
            HStack {
                Text("1:12"); Spacer(); Text("-2:31")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}

struct CompactPlayer: View {
    @Binding var isPlaying: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                Artwork(size: 52, radius: 10)
                VStack(alignment: .leading) {
                    Text("Midnight Static").font(.headline)
                    Text("The Lanterns").foregroundStyle(.secondary)
                }
                Spacer()
            }
            Scrubber()
            TransportControls(isPlaying: $isPlaying, scale: 0.7)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }
}

struct QueueView: View {
    @Environment(\.mantle) private var mantle

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Up Next").font(.title2.bold())
                Spacer()
                Button("Now Playing", systemImage: "arrow.up.left.and.arrow.down.right") { mantle.expand() }
                    .labelStyle(.iconOnly)
            }
            ForEach(["Glass Harbour", "Low Orbit", "Paper Moons", "Tidal", "Northern Line", "Afterglow"], id: \.self) { title in
                HStack(spacing: 12) {
                    Artwork(size: 40, radius: 6)
                    VStack(alignment: .leading) {
                        Text(title)
                        Text("The Lanterns").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
    }
}

struct NowPlaying: View {
    @Binding var isPlaying: Bool
    @Environment(\.mantle) private var mantle

    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 14) {
                Artwork(size: 44, radius: 8)
                VStack(alignment: .leading) {
                    Text("Midnight Static").font(.headline)
                    Text("The Lanterns").foregroundStyle(.secondary)
                }
                Spacer()
                Button(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill") { isPlaying.toggle() }
                    .contentTransition(.symbolEffect(.replace))
                    .font(.title2)
                Button("Close", systemImage: "chevron.down") { mantle.collapse() }
                    .font(.title3.weight(.semibold))
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            Scrubber()
            Artwork(size: 280, radius: 16)
                .scaleEffect(isPlaying ? 1 : 0.86)
                .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
                .animation(.spring(duration: 0.5, bounce: 0.3), value: isPlaying)
            TransportControls(isPlaying: $isPlaying)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
    }
}

struct RevealPlayer: View {
    @Binding var isPlaying: Bool
    var artworkCollapseMode: MantleCollapseMode = .automatic
    @Environment(\.mantle) private var mantle

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Named, so it can be presented with `.revealed("header")`.
                Detent(id: "header") {
                    HStack(spacing: 14) {
                        Artwork(size: 44, radius: 8)
                        VStack(alignment: .leading) {
                            Text("Midnight Static").font(.headline)
                            Text("The Lanterns").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill") { isPlaying.toggle() }
                            .contentTransition(.symbolEffect(.replace))
                            .font(.title2)
                        Button("Close", systemImage: "chevron.down") { mantle.collapse() }
                            .font(.title3.weight(.semibold))
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    Scrubber().padding(.top, 16)
                }
                Detent(id: "artwork") {
                    Artwork(size: 280, radius: 16)
                        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
                    TransportControls(isPlaying: $isPlaying).padding(.top, 28)
                }
                .mantleCollapseMode(artworkCollapseMode)
                VStack(alignment: .leading, spacing: 14) {
                    Text("Up Next").font(.title2.bold())
                    ForEach(1...20, id: \.self) { i in
                        HStack(spacing: 12) {
                            Artwork(size: 40, radius: 6)
                            VStack(alignment: .leading) {
                                Text("Track \(i)")
                                Text("The Lanterns").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
    }
}

// MARK: - Filler

struct AlbumGrid: View {
    let title: String

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 20) {
                ForEach(0..<24) { i in
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(hue: Double(i) / 24, saturation: 0.6, brightness: 0.85).gradient)
                            .aspectRatio(1, contentMode: .fit)
                        Text("Album \(i + 1)").font(.subheadline.weight(.medium))
                        Text("Artist").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(title)
    }
}

#Preview {
    ContentView()
}
