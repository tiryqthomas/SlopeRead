import SwiftUI

struct ContentView: View {
    @State private var model = SlopeModel()
    @State private var showCalibration = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                header
                HStack(spacing: 14) {
                    card(title: "Along the line",
                         value: model.upPercent,
                         positive: "Uphill", negative: "Downhill")
                    card(title: "Across the line",
                         value: model.sidePercent,
                         positive: "Right side higher", negative: "Left side higher")
                }
            }
            .padding(20)
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .sheet(isPresented: $showCalibration) { CalibrationView(model: model) }
    }

    private var header: some View {
        HStack {
            Label(statusText, systemImage: model.isLocked ? "lock.fill" : "dot.radiowaves.left.and.right")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
            if !model.isFlat {
                Text("Lay the phone flat, screen up")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Label("Screen top toward hole", systemImage: "arrow.up")
                .font(.subheadline).foregroundStyle(.secondary)
            Button { showCalibration = true } label: {
                Label(model.hasCalibration ? "Calibrated" : "Calibrate", systemImage: "scope")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 14).padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
    }

    private var statusText: String {
        if model.isLocked { return "Locked" }
        if model.stillProgress > 0 { return "Hold still…" }
        return "Live"
    }

    private func card(title: String, value: Double, positive: String, negative: String) -> some View {
        let level = abs(value) < 0.005
        return VStack(spacing: 10) {
            Text(title).font(.headline).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(String(format: "%.2f%%", abs(value)))
                .font(.system(size: 76, weight: .semibold, design: .default))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText(value: abs(value)))
            Text(level ? "Level" : (value > 0 ? positive : negative))
                .font(.title3.weight(.medium))
            Spacer(minLength: 0)
            gauge(value)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
        .opacity(model.isFlat ? 1 : 0.4)
    }

    /// Centered bar, full scale ±5 %.
    private func gauge(_ v: Double) -> some View {
        GeometryReader { g in
            let half = g.size.width / 2
            let frac = max(-1, min(1, v / 5))
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(.white)
                    .frame(width: abs(frac) * half)
                    .offset(x: frac >= 0 ? half : half + frac * half)
                Rectangle().fill(.white.opacity(0.6)).frame(width: 2).offset(x: half - 1)
            }
        }
        .frame(height: 8)
    }
}
