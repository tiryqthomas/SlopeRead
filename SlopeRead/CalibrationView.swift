import SwiftUI
import AudioToolbox
import UIKit

/// Two-position calibration: cancels the tilt caused by the camera bump on the back of the phone.
/// Start begins the process; each reading is taken automatically once the phone has settled.
struct CalibrationView: View {
    var model: SlopeModel
    @Environment(\.dismiss) private var dismiss

    private enum Phase { case ready, waitingUp, doneUp, waitingDown, doneAll }

    @State private var phase: Phase = .ready
    @State private var faceUp: SIMD3<Double>?

    private var step: Int { (phase == .waitingDown || phase == .doneUp || phase == .doneAll) ? 2 : 1 }

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
                content
                Spacer(minLength: 0)
                if phase == .ready, model.hasCalibration {
                    Button("Clear calibration", role: .destructive) { model.clearCalibration(); dismiss() }
                        .font(.footnote)
                }
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
        .onChange(of: readyToTake) { _, ready in
            if ready { take() }
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .ready:
            Text("Two readings, taken automatically when the phone is still.")
                .font(.title3).multilineTextAlignment(.center)
            button("Start") { phase = .waitingUp }

        case .waitingUp, .waitingDown:
            Text("Step \(step) of 2").font(.subheadline).foregroundStyle(.secondary)
            Text(phase == .waitingUp
                 ? "Place the phone face up on any flat, stable surface. Top edge pointing away from you."
                 : "Flip it face down like a book. Same spot, top edge still pointing away.")
                .multilineTextAlignment(.center)
                .font(.title3)
            Text("Hold still…").font(.subheadline).foregroundStyle(.secondary)
            ProgressView(value: model.stillProgress)
                .tint(.white).frame(maxWidth: 260)
            Button("Cancel") { faceUp = nil; phase = .ready }
                .font(.footnote)

        case .doneUp, .doneAll:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 64))
            Text("Done !").font(.system(size: 44, weight: .semibold))
            if phase == .doneAll {
                Text("Calibration saved").font(.title3).foregroundStyle(.secondary)
            }
        }
    }

    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 36).padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    /// True when the phone has settled in the pose the current step needs.
    private var readyToTake: Bool {
        guard let m = model.stillMean else { return false }
        switch phase {
        case .waitingUp: return m.z > 0.98
        case .waitingDown: return m.z < -0.98
        default: return false
        }
    }

    private func take() {
        guard let m = model.stillMean else { return }
        switch phase {
        case .waitingUp:
            faceUp = m
            phase = .doneUp
            feedback()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if phase == .doneUp { phase = .waitingDown }
            }
        case .waitingDown:
            guard let up = faceUp else { return }
            model.saveCalibration(faceUp: up, faceDown: m)
            phase = .doneAll
            feedback()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { dismiss() }
        default:
            break
        }
    }

    private func feedback() {
        AudioServicesPlaySystemSound(1057)   // "Tink"; muted by the silent switch
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
