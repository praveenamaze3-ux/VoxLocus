//
//  NLPTodoExtractor.swift
//  VoxLocus
//
//  Created by Praveen V on 30/06/26.
//

import NaturalLanguage
import Foundation

struct NLPTodoExtractor {

    /// Verb-led cue phrases that strongly suggest an action item.
    private static let actionCues = [
        "remind me to", "need to", "have to", "should", "must",
        "don't forget to", "remember to", "todo", "to-do", "buy",
        "call", "email", "schedule", "book", "pick up", "pay",
        "send", "finish", "submit", "follow up", "plan to", "make sure to"
    ]

    /// Splits transcript into sentences, scores each for "action-ness", and
    /// returns cleaned-up todo strings for anything above the threshold.
    nonisolated static func extractTodos(from transcript: String) async -> [TodoItem] {
        await Task.detached(priority: .userInitiated) {
            guard !transcript.isEmpty else { return [] }

            var sentences: [String] = []
            let tokenizer = NLTokenizer(unit: .sentence)
            tokenizer.string = transcript
            tokenizer.enumerateTokens(in: transcript.startIndex..<transcript.endIndex) { range, _ in
                sentences.append(String(transcript[range]).trimmingCharacters(in: .whitespacesAndNewlines))
                return true
            }

            var results: [TodoItem] = []

            for sentence in sentences where !sentence.isEmpty {
                if isActionable(sentence) {
                    results.append(TodoItem(text: cleanedTodoText(from: sentence)))
                }
            }
            return results
        }.value
    }

    nonisolated private static func isActionable(_ sentence: String) -> Bool {
        let lower = sentence.lowercased()

        // 1. Cue-phrase heuristic.
        if actionCues.contains(where: { lower.contains($0) }) {
            return true
        }

        // 2. Grammatical heuristic: sentence starts with (or strongly leads
        // with) a base-form verb, e.g. "Buy milk." / "Call the dentist."
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = sentence
        var startsWithVerb = false
        tagger.enumerateTags(in: sentence.startIndex..<sentence.endIndex, unit: .word, scheme: .lexicalClass) { tag, range in
            if range.lowerBound == sentence.startIndex, tag == .verb {
                startsWithVerb = true
            }
            return false // only need the first token
        }
        return startsWithVerb
    }

    nonisolated private static func cleanedTodoText(from sentence: String) -> String {
        var text = sentence
        for cue in actionCues {
            if let range = text.range(of: cue, options: [.caseInsensitive]) {
                text.removeSubrange(text.startIndex..<range.upperBound)
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(1).uppercased() + text.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst()
    }

    /// Very lightweight category classifier based on keyword matching —
    /// swap for an NLModel / Core ML classifier later if you want it learned.
    nonisolated static func suggestCategory(for transcript: String) -> NoteCategory {
        let lower = transcript.lowercased()
        if ["buy", "store", "grocery", "shop", "purchase"].contains(where: lower.contains) { return .shopping }
        if ["meeting", "deadline", "project", "client", "boss", "office"].contains(where: lower.contains) { return .work }
        if ["doctor", "gym", "workout", "medicine", "appointment", "health"].contains(where: lower.contains) { return .health }
        if ["idea", "what if", "concept", "brainstorm"].contains(where: lower.contains) { return .ideas }
        if ["family", "home", "friend", "personal"].contains(where: lower.contains) { return .personal }
        return .other
    }
}
