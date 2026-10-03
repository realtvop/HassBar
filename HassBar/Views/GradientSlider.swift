//
//  GradientSlider.swift
//  HassBar
//
//  Created by Codex on 2026/6/30.
//

import SwiftUI

enum GradientSliderTrackStyle {
    case fullGradient([Color])
    case valueFill(Color)
}

struct GradientSlider: View {
    @Binding var value: Double
    @Environment(\.isEnabled) private var isEnabled
    @State private var scrollCommitTask: Task<Void, Never>?

    let range: ClosedRange<Double>
    let step: Double
    let trackStyle: GradientSliderTrackStyle
    let onCommit: (Double) async -> Void
    var onEditingChanged: (Bool) -> Void = { _ in }

    private let thumbSize: CGFloat = 13
    private let trackHeight: CGFloat = 6
    private let scrollSensitivity = 0.35
    private let scrollCommitDelay: Duration = .milliseconds(180)

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, thumbSize)
            let trackWidth = max(width - thumbSize, 1)
            let progress = normalizedValue

            ZStack(alignment: .leading) {
                track(progress: progress, trackWidth: trackWidth)

                Circle()
                    .fill(.background)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 0.5)
                    .overlay {
                        Circle()
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    }
                    .position(x: thumbSize / 2 + trackWidth * progress, y: proxy.size.height / 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .overlay {
                SliderEventView(isEnabled: isEnabled) { locationX in
                    onEditingChanged(true)
                    updateValue(from: locationX, trackWidth: trackWidth)
                } onScroll: { delta in
                    onEditingChanged(true)
                    updateValue(byScrollDelta: delta)
                    scheduleScrollCommit()
                } onCommit: {
                    scrollCommitTask?.cancel()
                    commitCurrentValue()
                } onKeyAdjustment: { direction in
                    adjustValue(direction: direction)
                }
            }
        }
        .frame(height: 18)
        .accessibilityElement()
        .accessibilityValue(value.formatted(.number.precision(.fractionLength(0...1))))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjustValue(direction: 1)
            case .decrement: adjustValue(direction: -1)
            @unknown default: break
            }
        }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { scrollCommitTask?.cancel(); onEditingChanged(false) }
        }
        .onDisappear {
            scrollCommitTask?.cancel()
            onEditingChanged(false)
        }
    }

    private var normalizedValue: CGFloat {
        guard range.upperBound > range.lowerBound else { return 0 }
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        return CGFloat((clamped - range.lowerBound) / (range.upperBound - range.lowerBound))
    }

    @ViewBuilder
    private func track(progress: CGFloat, trackWidth: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color(nsColor: .separatorColor).opacity(0.4))
                .frame(width: trackWidth, height: trackHeight)
                .padding(.leading, thumbSize / 2)
            switch trackStyle {
            case .fullGradient(let colors):
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: colors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: trackWidth, height: trackHeight)
                    .padding(.leading, thumbSize / 2)
            case .valueFill(let color):
                Capsule()
                    .fill(color)
                    .frame(width: max(trackWidth * progress, 0), height: trackHeight)
                    .padding(.leading, thumbSize / 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func updateValue(from locationX: CGFloat, trackWidth: CGFloat) {
        let clampedX = min(max(locationX - thumbSize / 2, 0), trackWidth)
        if clampedX <= 0 {
            value = range.lowerBound
            return
        }
        if clampedX >= trackWidth {
            value = range.upperBound
            return
        }

        let rawValue = range.lowerBound + Double(clampedX / trackWidth) * (range.upperBound - range.lowerBound)
        value = SliderValueScale.quantized(rawValue, range: range, step: step)
    }

    private func updateValue(byScrollDelta delta: CGFloat) {
        guard delta != 0, range.upperBound > range.lowerBound else { return }

        let valueRange = range.upperBound - range.lowerBound
        let scrollStep = max(step, valueRange / 100)
        let rawValue = value + Double(delta) * scrollStep * scrollSensitivity
        value = SliderValueScale.quantized(rawValue, range: range, step: step)
    }

    private func scheduleScrollCommit() {
        scrollCommitTask?.cancel()
        let committedValue = value
        scrollCommitTask = Task {
            try? await Task.sleep(for: scrollCommitDelay)
            guard !Task.isCancelled else { return }
            onEditingChanged(false)
            await onCommit(committedValue)
        }
    }

    private func adjustValue(direction: Double) {
        guard isEnabled else { return }
        value = SliderValueScale.quantized(value + direction * step, range: range, step: step)
        commitCurrentValue()
    }

    private func commitCurrentValue() {
        guard isEnabled else { return }
        onEditingChanged(false)
        let committedValue = value
        Task {
            onEditingChanged(false)
            await onCommit(committedValue)
        }
    }
}

private struct SliderEventView: NSViewRepresentable {
    let isEnabled: Bool
    let onDrag: (CGFloat) -> Void
    let onScroll: (CGFloat) -> Void
    let onCommit: () -> Void
    let onKeyAdjustment: (Double) -> Void

    func makeNSView(context: Context) -> SliderEventCatcherView {
        let view = SliderEventCatcherView()
        view.isEnabled = isEnabled
        view.onKeyAdjustment = onKeyAdjustment
        view.onDrag = onDrag
        view.onScroll = onScroll
        view.onCommit = onCommit
        return view
    }

    func updateNSView(_ nsView: SliderEventCatcherView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.onKeyAdjustment = onKeyAdjustment
        nsView.onDrag = onDrag
        nsView.onScroll = onScroll
        nsView.onCommit = onCommit
    }

    final class SliderEventCatcherView: NSView {
        var isEnabled = true
        var onKeyAdjustment: ((Double) -> Void)?
        var onDrag: ((CGFloat) -> Void)?
        var onScroll: ((CGFloat) -> Void)?
        var onCommit: (() -> Void)?

        override var acceptsFirstResponder: Bool { isEnabled }

        override func mouseDown(with event: NSEvent) {
            guard isEnabled else { return }
            window?.makeFirstResponder(self)
            handleDrag(event)
        }

        override func mouseDragged(with event: NSEvent) {
            handleDrag(event)
        }

        override func mouseUp(with event: NSEvent) {
            guard isEnabled else { return }
            handleDrag(event)
            onCommit?()
        }

        override func scrollWheel(with event: NSEvent) {
            guard isEnabled else { return }
            guard event.hasPreciseScrollingDeltas else {
                super.scrollWheel(with: event)
                return
            }
            guard event.momentumPhase == [] else { return }

            let horizontalDelta = event.scrollingDeltaX
            guard abs(horizontalDelta) > abs(event.scrollingDeltaY), horizontalDelta != 0 else {
                super.scrollWheel(with: event)
                return
            }

            let directionMultiplier: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
            onScroll?(horizontalDelta * directionMultiplier)

            if event.phase == .ended || event.momentumPhase == .ended {
                onCommit?()
            }
        }

        override func keyDown(with event: NSEvent) {
            guard isEnabled else { return }
            switch event.keyCode {
            case 123, 125: onKeyAdjustment?(-1)
            case 124, 126: onKeyAdjustment?(1)
            default: super.keyDown(with: event)
            }
        }

        private func handleDrag(_ event: NSEvent) {
            guard isEnabled else { return }
            let location = convert(event.locationInWindow, from: nil)
            onDrag?(location.x)
        }
    }
}
