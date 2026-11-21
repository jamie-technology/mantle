import UIKit

/// Calls back once per display frame, asking for up to 120Hz, while the mantle
/// snaps.
///
/// Snaps spring only the sheet's top edge and derive everything else from it,
/// like the SwiftUI engine. A Core Animation spring would animate size and
/// position independently, so a bounce would overshoot the size too and squash
/// the capsule. The per-frame work is a few layer property sets, with no content
/// layout.
///
/// On iPhone, the app's Info.plist needs `CADisableMinimumFrameDurationOnPhone`
/// set to `YES` for this to run above 60Hz.
@MainActor
final class MantleFrameDriver: NSObject {
    private var link: CADisplayLink?
    /// Returns `false` to stop.
    private var onFrame: (@MainActor (CFTimeInterval) -> Bool)?

    var isRunning: Bool { link != nil }

    /// Starts calling `onFrame` with each frame's target timestamp, replacing any
    /// previous callback.
    func start(_ onFrame: @escaping @MainActor (CFTimeInterval) -> Bool) {
        self.onFrame = onFrame
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        onFrame = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let onFrame, onFrame(link.targetTimestamp) else {
            stop()
            return
        }
    }
}
