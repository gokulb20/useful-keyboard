import Foundation
import WebRTCAec3Bridge
import os

protocol MeetingAecProcessingEngine {
    func analyzeRenderFrame(_ frame: [Int16]) -> Bool
    func processCaptureFrame(_ frame: [Int16]) -> [Int16]?
}

final class MeetingAecProcessor {
    private struct State {
        var pendingRender: [Int16] = []
        var pendingCapture: [Int16] = []
    }

    static let sampleRate = 16_000
    static let frameSampleCount = sampleRate / 100

    private let engine: any MeetingAecProcessingEngine
    private let frameSampleCount: Int
    private let lock = OSAllocatedUnfairLock(initialState: State())

    init(
        sampleRate: Int = sampleRate,
        engine: (any MeetingAecProcessingEngine)? = nil
    ) throws {
        self.frameSampleCount = sampleRate / 100
        if let engine {
            self.engine = engine
        } else if let engine = WebRTCAec3ProcessingEngine(sampleRate: sampleRate) {
            self.engine = engine
        } else {
            throw NSError(
                domain: "MeetingAecProcessor",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to initialize WebRTC AEC3."]
            )
        }
    }

    func appendRender(_ samples: [Int16]) {
        guard !samples.isEmpty else { return }
        lock.withLock { state in
            state.pendingRender.append(contentsOf: samples)
            while state.pendingRender.count >= frameSampleCount {
                let frame = Array(state.pendingRender.prefix(frameSampleCount))
                state.pendingRender.removeFirst(frameSampleCount)
                _ = engine.analyzeRenderFrame(frame)
            }
        }
    }

    func processCapture(_ samples: [Int16]) -> [Int16] {
        guard !samples.isEmpty else { return [] }
        return lock.withLock { state in
            state.pendingCapture.append(contentsOf: samples)

            var output: [Int16] = []
            while state.pendingCapture.count >= frameSampleCount {
                let frame = Array(state.pendingCapture.prefix(frameSampleCount))
                state.pendingCapture.removeFirst(frameSampleCount)
                output.append(contentsOf: engine.processCaptureFrame(frame) ?? frame)
            }
            return output
        }
    }

    func flushCaptureRemainder() -> [Int16] {
        lock.withLock { state in
            guard !state.pendingCapture.isEmpty else { return [] }

            let originalCount = state.pendingCapture.count
            var padded = state.pendingCapture
            state.pendingCapture.removeAll(keepingCapacity: false)

            if padded.count < frameSampleCount {
                padded.append(contentsOf: repeatElement(0, count: frameSampleCount - padded.count))
            }

            let processed = engine.processCaptureFrame(padded) ?? padded
            return Array(processed.prefix(originalCount))
        }
    }

    func reset() {
        lock.withLock { state in
            state.pendingRender.removeAll(keepingCapacity: false)
            state.pendingCapture.removeAll(keepingCapacity: false)
        }
    }
}

private final class WebRTCAec3ProcessingEngine: MeetingAecProcessingEngine {
    private let handle: OpaquePointer

    init?(sampleRate: Int, renderChannels: Int = 1, captureChannels: Int = 1) {
        guard let handle = WebRTCAec3Create(Int32(sampleRate), Int32(renderChannels), Int32(captureChannels)) else {
            return nil
        }
        self.handle = handle
    }

    deinit {
        WebRTCAec3Destroy(handle)
    }

    func analyzeRenderFrame(_ frame: [Int16]) -> Bool {
        frame.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return false }
            return WebRTCAec3AnalyzeRender(handle, baseAddress, Int32(frame.count))
        }
    }

    func processCaptureFrame(_ frame: [Int16]) -> [Int16]? {
        var output = [Int16](repeating: 0, count: frame.count)
        let success = frame.withUnsafeBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                guard let inputBaseAddress = inputBuffer.baseAddress,
                      let outputBaseAddress = outputBuffer.baseAddress else {
                    return false
                }
                return WebRTCAec3ProcessCapture(handle, inputBaseAddress, Int32(frame.count), outputBaseAddress)
            }
        }
        return success ? output : nil
    }
}
