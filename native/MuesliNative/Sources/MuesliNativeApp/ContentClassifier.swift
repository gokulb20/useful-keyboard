import Foundation

/// Classifies transcribed speech content via a local Ollama LLM.
/// Gracefully falls back to empty hints if Ollama is unavailable.
final class ContentClassifier: @unchecked Sendable {

    /// Ollama API endpoint.
    private let baseURL: URL
    /// Model to use for classification.
    private var model: String

    /// Minimum interval between classification requests (debounce).
    private let minInterval: TimeInterval = 15.0
    private var lastClassificationTime: Date = .distantPast

    private let session: URLSession

    init(
        baseURL: URL = URL(string: "http://localhost:11434")!,
        model: String = "llama3.2:1b"
    ) {
        self.baseURL = baseURL
        self.model = model
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: config)
    }

    func setModel(_ model: String) {
        self.model = model
    }

    /// Classify a chunk of transcribed text. Returns content hints sorted by confidence.
    /// Returns empty array if Ollama is unavailable or classification fails.
    func classify(_ text: String) async -> [ContentHint] {
        let now = Date()
        guard now.timeIntervalSince(lastClassificationTime) >= minInterval else {
            return []
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        lastClassificationTime = now

        do {
            return try await callOllama(text: text)
        } catch {
            fputs("[context-classifier] Ollama unavailable: \(error.localizedDescription)\n", stderr)
            return []
        }
    }

    /// Check if Ollama is reachable.
    func isAvailable() async -> Bool {
        let url = baseURL.appendingPathComponent("api/tags")
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Private

    private func callOllama(text: String) async throws -> [ContentHint] {
        let url = baseURL.appendingPathComponent("api/generate")

        let prompt = """
        Classify the following transcribed speech into one or more categories. \
        Return ONLY a JSON array of objects with "category" and "confidence" (0.0-1.0) fields.

        Categories: standup, codeReview, planning, oneOnOne, interview, presentation, casual, technical, general

        Example response: [{"category": "standup", "confidence": 0.85}, {"category": "technical", "confidence": 0.4}]

        Text to classify:
        \(text.prefix(1000))
        """

        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "format": "json",
            "options": [
                "temperature": 0.1,
                "num_predict": 200,
            ],
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return []
        }

        return parseResponse(data)
    }

    private func parseResponse(_ data: Data) -> [ContentHint] {
        // Ollama returns {"response": "...", ...} where response contains the model's text output
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String else {
            return []
        }

        // Parse the JSON array from the model's response
        guard let responseData = responseText.data(using: .utf8),
              let hints = try? JSONSerialization.jsonObject(with: responseData) as? [[String: Any]] else {
            return []
        }

        return hints.compactMap { hint in
            guard let categoryStr = hint["category"] as? String,
                  let category = ContentCategory(rawValue: categoryStr),
                  let confidence = hint["confidence"] as? Double else { return nil }
            return ContentHint(category: category, confidence: max(0, min(1, confidence)))
        }
        .sorted { $0.confidence > $1.confidence }
    }
}
