import Foundation

nonisolated enum SliderValueScale {
    static func quantized(_ value: Double, range: ClosedRange<Double>, step: Double) -> Double {
        guard value.isFinite else { return range.lowerBound }
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        guard step.isFinite, step > 0, clamped > range.lowerBound, clamped < range.upperBound else { return clamped }
        let stepped = range.lowerBound + ((clamped - range.lowerBound) / step).rounded() * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }
}

