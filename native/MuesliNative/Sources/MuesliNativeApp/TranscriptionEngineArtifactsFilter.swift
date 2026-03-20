import Foundation

/// Removes known model hallucination artifacts emitted on silence or blank input.
/// Applied as post-processing after ASR, before filler word filtering.
struct TranscriptionEngineArtifactsFilter {

    private static let artifacts: Set<String> = [
        "[blank_audio]",
    ]

    /// Returns an empty string if the entire transcription is a known blank-audio artifact;
    /// otherwise returns the text unchanged.
    static func apply(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return artifacts.contains(trimmed.lowercased()) ? "" : text
    }
}
