import SwiftUI
import AudioToolbox
import UIKit

/// Two-position calibration: cancels the tilt caused by the camera bump on the back of the phone.
struct CalibrationView: View {
    var model: SlopeModel
    @Environment(\.dismiss) private var dismiss
    @State private var faceUp: SIMD3<Double>?
    @State private var done = false

    private var step: Int { faceUp == nil ? 1 : 2 }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                HStack {
                    Text("Calibrate").font(.title2.weight(.semibold))
                    Spacer()
                    Button("Close") { dismiss() }
                }
                Spacer(minLength: 0)
                if done {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 52))
                    Text("Calibration saved").font(.title3.weight(.medium))
                } else {
                    Text("Step \(step) of 2").font(.subheadline).foregroundStyle(.secondary)
                    Text(step == 1
                         ? "Place the phone face up on any flat, stable surface. Top edge pointing away from you."
                         : "Flip it face down like a book. Same spot, top edge still pointing away.")
                        .multilineTextAlignment(.center)
                        .font(.title3)
                    ProgressView(value: model.stillProgress)
                        .tint(.white).frame(maxWidth: 260)
                    Button(action: capture) {
                        Text("Capture")
                            .font(.headline)
                            .padding(.horizontal, 36).padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .disabled(!canCapture)
                    .opacity(canCapture ? 1 : 0.4)
                }
                Spacer(minLength: 0)
                if model.hasCalibration {
                    Button("Clear calibration", role: .destructive) { model.clearCalibration(); dismiss() }
                        .font(.footnote)
                }
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
    }

    private var canCapture: Bool {
        guard let m = model.stillMean else { return false }
        return step == 1 ? m.z > 0.98 : m.z < -0.98
    }

    private func capture() {
        guard let m = model.stillMean else { return }
        if let up = faceUp {
            model.saveCalibration(faceUp: up, faceDown: m)
            done = true
            AudioServicesPlaySystemSound(1057)   // "Tink"; muted by the silent switch
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
        } else {
            faceUp = m
        }
    }
}
