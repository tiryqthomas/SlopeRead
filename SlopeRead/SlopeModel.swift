import CoreMotion
import Observation
import UIKit

/// Reads the phone's gravity vector and turns it into slope percentages.
/// Axes (device frame): +y = top edge (point it toward the hole), +x = right edge.
/// u = "up" vector = -gravity. u.y > 0 → top edge higher (uphill to hole). u.x > 0 → right side higher.
@Observable
final class SlopeModel {
    struct Bias: Codable { var x: Double; var y: Double }

    // Tunables
    private let window = 2.0            // seconds of stillness before locking
    private let spreadLimit = 0.001     // max spread of u (≈0.1 %) inside the window
    private let stillRate = 0.03        // rad/s
    private let unlockRate = 0.15       // rad/s
    private let unlockShift = 0.004     // ≈0.4 % change releases the lock
    private let flatLimit = 0.9         // |u.z| must exceed this (≈ within 25° of flat)

    private struct Sample { let t: Double; let u: SIMD3<Double> }

    private let motion = CMMotionManager()
    private var buffer: [Sample] = []
    private var lockedRaw: SIMD3<Double>?

    // Published state
    var upPercent = 0.0        // + = uphill toward hole
    var sidePercent = 0.0      // + = right side higher
    var isLocked = false
    var isFlat = false
    var faceUp = true
    var stillMean: SIMD3<Double>?   // raw mean when phone has been still for `window`
    var stillProgress = 0.0         // 0…1 toward lock
    var yaw = 0.0                   // radians, arbitrary reference (used to check the 180° spin)
    var bias = Bias(x: 0, y: 0)
    var hasCalibration = false

    init() {
        if let d = UserDefaults.standard.data(forKey: "slope.bias.v2"),
           let b = try? JSONDecoder().decode(Bias.self, from: d) {
            bias = b
            hasCalibration = true
        }
    }

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        UIApplication.shared.isIdleTimerDisabled = true
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] m, _ in
            guard let self, let m else { return }
            self.process(m)
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: Calibration

    /// up = reading face-up on the surface, other = reading face-up again after spinning the phone ~180° flat in place.
    /// The surface tilt reverses between the two readings while the phone's own offset (camera bump) does not,
    /// so the average is the offset.
    func saveCalibration(faceUp up: SIMD3<Double>, rotated other: SIMD3<Double>) {
        let b = Bias(x: (up.x + other.x) / 2, y: (up.y + other.y) / 2)
        bias = b
        hasCalibration = true
        if let d = try? JSONEncoder().encode(b) { UserDefaults.standard.set(d, forKey: "slope.bias.v2") }
    }

    func clearCalibration() {
        bias = Bias(x: 0, y: 0)
        hasCalibration = false
        UserDefaults.standard.removeObject(forKey: "slope.bias.v2")
    }

    // MARK: Processing

    private func percent(_ s: Double) -> Double {
        let c = max(-0.99, min(0.99, s))
        return 100 * c / (1 - c * c).squareRoot()
    }

    /// Landscape: the screen's "up" (toward the hole) runs along the device's x axis.
    /// +1 when it points along +x, -1 when along -x.
    private var holeSign = 1.0

    private func updateOrientation() {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        switch scene?.interfaceOrientation {
        case .landscapeLeft: holeSign = -1
        case .landscapeRight: holeSign = 1
        default: break
        }
    }

    private func publish(_ u: SIMD3<Double>) {
        upPercent = percent(holeSign * (u.x - bias.x))       // along the line, + = uphill
        sidePercent = percent(-holeSign * (u.y - bias.y))    // across the line, + = right side higher
    }

    private func process(_ m: CMDeviceMotion) {
        updateOrientation()
        let u = SIMD3(-m.gravity.x, -m.gravity.y, -m.gravity.z)
        let r = m.rotationRate
        let w = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()
        let t = m.timestamp

        buffer.append(Sample(t: t, u: u))
        while let f = buffer.first, t - f.t > window { buffer.removeFirst() }

        faceUp = u.z > 0
        yaw = m.attitude.yaw
        isFlat = abs(u.z) > flatLimit

        let span = (buffer.last?.t ?? t) - (buffer.first?.t ?? t)
        var mean = SIMD3<Double>(0, 0, 0)
        var lo = u, hi = u
        for s in buffer {
            mean += s.u
            lo = SIMD3(min(lo.x, s.u.x), min(lo.y, s.u.y), min(lo.z, s.u.z))
            hi = SIMD3(max(hi.x, s.u.x), max(hi.y, s.u.y), max(hi.z, s.u.z))
        }
        mean /= Double(buffer.count)
        let steady = w < stillRate && (hi.x - lo.x) < spreadLimit && (hi.y - lo.y) < spreadLimit
        stillProgress = steady ? min(1, span / window) : 0
        stillMean = (steady && span >= window * 0.95) ? mean : nil

        if let locked = lockedRaw {
            if w > unlockRate || abs(u.x - locked.x) > unlockShift || abs(u.y - locked.y) > unlockShift {
                lockedRaw = nil
                isLocked = false
                buffer.removeAll()
                publish(u)
            }
        } else if let sm = stillMean, sm.z > flatLimit {
            lockedRaw = sm
            isLocked = true
            publish(sm)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            publish(u)
        }
    }
}
