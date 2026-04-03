import Testing
import Foundation
@testable import MuesliNativeApp

@Suite("ContextDetector")
struct ContextDetectorTests {

    private let detector = ContextDetector()

    // MARK: - Native app mappings

    @Test("Apple Mail maps to email")
    func appleMail() {
        #expect(detector.detect(bundleID: "com.apple.mail", windowTitle: nil) == .email)
    }

    @Test("Messages maps to imessage")
    func messages() {
        #expect(detector.detect(bundleID: "com.apple.MobileSMS", windowTitle: nil) == .imessage)
    }

    @Test("Notes maps to notes")
    func notes() {
        #expect(detector.detect(bundleID: "com.apple.Notes", windowTitle: nil) == .notes)
    }

    @Test("ChatGPT app maps to ai-prompt")
    func chatGPTApp() {
        #expect(detector.detect(bundleID: "com.openai.chat", windowTitle: nil) == .aiPrompt)
    }

    @Test("VS Code maps to code")
    func vsCode() {
        #expect(detector.detect(bundleID: "com.microsoft.VSCode", windowTitle: nil) == .code)
    }

    @Test("Xcode maps to code")
    func xcode() {
        #expect(detector.detect(bundleID: "com.apple.dt.Xcode", windowTitle: nil) == .code)
    }

    @Test("Terminal maps to code")
    func terminal() {
        #expect(detector.detect(bundleID: "com.apple.Terminal", windowTitle: nil) == .code)
    }

    @Test("iTerm maps to code")
    func iterm() {
        #expect(detector.detect(bundleID: "com.googlecode.iterm2", windowTitle: nil) == .code)
    }

    @Test("Warp maps to code")
    func warp() {
        #expect(detector.detect(bundleID: "dev.warp.Warp-Stable", windowTitle: nil) == .code)
    }

    // MARK: - Browser title detection

    @Test("Chrome with Gmail title maps to email")
    func chromeGmail() {
        #expect(detector.detect(bundleID: "com.google.Chrome", windowTitle: "Inbox (3) - user@gmail.com - Gmail") == .email)
    }

    @Test("Safari with ChatGPT title maps to ai-prompt")
    func safariChatGPT() {
        #expect(detector.detect(bundleID: "com.apple.Safari", windowTitle: "ChatGPT") == .aiPrompt)
    }

    @Test("Firefox with Claude title maps to ai-prompt")
    func firefoxClaude() {
        #expect(detector.detect(bundleID: "org.mozilla.firefox", windowTitle: "Claude") == .aiPrompt)
    }

    @Test("Arc with Outlook title maps to email")
    func arcOutlook() {
        #expect(detector.detect(bundleID: "company.thebrowser.Browser", windowTitle: "Outlook - Calendar") == .email)
    }

    @Test("Brave with Gemini maps to ai-prompt")
    func braveGemini() {
        #expect(detector.detect(bundleID: "com.brave.Browser", windowTitle: "Gemini - Google AI") == .aiPrompt)
    }

    @Test("Chrome with Perplexity maps to ai-prompt")
    func chromePerplexity() {
        #expect(detector.detect(bundleID: "com.google.Chrome", windowTitle: "Perplexity AI") == .aiPrompt)
    }

    // MARK: - Browser with no matching title

    @Test("Chrome with unrecognized title falls back to general")
    func chromeGenericSite() {
        #expect(detector.detect(bundleID: "com.google.Chrome", windowTitle: "Wikipedia - Main Page") == .general)
    }

    @Test("Browser with nil title falls back to general")
    func browserNilTitle() {
        #expect(detector.detect(bundleID: "com.google.Chrome", windowTitle: nil) == .general)
    }

    @Test("Browser with empty title falls back to general")
    func browserEmptyTitle() {
        #expect(detector.detect(bundleID: "com.google.Chrome", windowTitle: "") == .general)
    }

    // MARK: - Fallback

    @Test("Unknown app maps to general")
    func unknownApp() {
        #expect(detector.detect(bundleID: "com.example.randomapp", windowTitle: nil) == .general)
    }

    @Test("Unknown bundle ID with window title still returns general")
    func unknownAppWithTitle() {
        #expect(detector.detect(bundleID: "com.example.randomapp", windowTitle: "Gmail") == .general)
    }

    // MARK: - Case insensitivity

    @Test("Browser title matching is case-insensitive")
    func caseInsensitive() {
        #expect(detector.detect(bundleID: "com.google.Chrome", windowTitle: "CHATGPT - New Chat") == .aiPrompt)
    }

    // MARK: - WritingContext raw values

    @Test("WritingContext raw values match expected strings")
    func rawValues() {
        #expect(WritingContext.email.rawValue == "email")
        #expect(WritingContext.imessage.rawValue == "imessage")
        #expect(WritingContext.aiPrompt.rawValue == "ai-prompt")
        #expect(WritingContext.notes.rawValue == "notes")
        #expect(WritingContext.code.rawValue == "code")
        #expect(WritingContext.general.rawValue == "general")
    }

    // MARK: - Native app takes precedence

    @Test("Native app mapping takes precedence over window title")
    func nativeAppPrecedence() {
        #expect(detector.detect(bundleID: "com.apple.mail", windowTitle: "ChatGPT mentioned in email") == .email)
    }
}
