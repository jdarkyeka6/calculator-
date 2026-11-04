import Foundation
import CoreMotion

/// Covers the vault when the SCREEN faces down for more than 0.4 seconds.
/// The caller locks the vault before optionally requesting an external app link.
/// iOS controls whether another app actually opens.
final class FaceDownMonitor {
    private let motion = CMMotionManager()
    private var startTime: Date?
    private var triggered = false

    func start(onFaceDown: @escaping () -> Void) {
        guard motion.isDeviceMotionAvailable else { return }
        triggered = false
        startTime = nil
        motion.deviceMotionUpdateInterval = 0.15
        motion.startDeviceMotionUpdates(to: .main) { [weak self] reading, _ in
            guard let self, let reading, !self.triggered else { return }
            if reading.gravity.z > 0.85 {
                if self.startTime == nil { self.startTime = Date() }
                if let first = self.startTime, Date().timeIntervalSince(first) >= 0.4 {
                    self.triggered = true
                    self.stop()
                    onFaceDown()
                }
            } else {
                self.startTime = nil
            }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        startTime = nil
    }
}
