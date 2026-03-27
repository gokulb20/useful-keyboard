import Foundation
import Testing
@testable import MuesliNativeApp

@Suite("MeetingAecProcessor")
struct MeetingAecProcessorTests {

    @Test("buffers render and capture samples into 10 ms frames")
    func buffersIntoFrames() throws {
        let engine = FakeMeetingAecEngine()
        let processor = try MeetingAecProcessor(engine: engine)

        processor.appendRender(Array(repeating: 1, count: 100))
        #expect(engine.renderFrames.isEmpty)

        processor.appendRender(Array(repeating: 2, count: 60))
        #expect(engine.renderFrames.count == 1)
        #expect(engine.renderFrames[0].count == 160)
        #expect(engine.renderFrames[0].prefix(100).allSatisfy { $0 == 1 })
        #expect(engine.renderFrames[0].suffix(60).allSatisfy { $0 == 2 })

        let firstCaptureOutput = processor.processCapture(Array(repeating: 5, count: 200))
        #expect(firstCaptureOutput.count == 160)
        #expect(engine.captureFrames.count == 1)
        #expect(engine.captureFrames[0] == Array(repeating: 5, count: 160))

        let flushedOutput = processor.flushCaptureRemainder()
        #expect(flushedOutput.count == 40)
        #expect(flushedOutput.allSatisfy { $0 == 5 })
        #expect(engine.captureFrames.count == 2)
        #expect(engine.captureFrames[1].count == 160)
    }

    @Test("falls back to raw capture frame when AEC processing fails")
    func fallsBackToRawCaptureFrame() throws {
        let engine = FakeMeetingAecEngine()
        engine.shouldFailCapture = true
        let processor = try MeetingAecProcessor(engine: engine)
        let input = Array(0..<MeetingAecProcessor.frameSampleCount).map(Int16.init)

        let output = processor.processCapture(input)

        #expect(output == input)
    }
}

private final class FakeMeetingAecEngine: MeetingAecProcessingEngine {
    var renderFrames: [[Int16]] = []
    var captureFrames: [[Int16]] = []
    var shouldFailCapture = false

    func analyzeRenderFrame(_ frame: [Int16]) -> Bool {
        renderFrames.append(frame)
        return true
    }

    func processCaptureFrame(_ frame: [Int16]) -> [Int16]? {
        captureFrames.append(frame)
        return shouldFailCapture ? nil : frame
    }
}
