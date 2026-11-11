import Foundation

/// A persisted set of event IDs, triple-redundant like the Flutter
/// `PersistedIdSet`: a JSON preference string, a JSON file mirror, and a
/// legacy string-list recovery path. Loads take the union of everything
/// found, so one storage hiccup can never silently drop the user's list.
/// Ported from `lib/services/persisted_ids.dart`.
final class PersistedIdSet {
    private let key: String
    private let defaults: UserDefaults
    private let mirrorURL: URL?

    /// - Parameters:
    ///   - key: the preference key, e.g. "follow.events".
    ///   - fileName: the mirror file in the app's documents, e.g.
    ///     "follow_events.json".
    init(key: String, fileName: String, defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        self.mirrorURL = documents?.appendingPathComponent(fileName)
    }

    /// Loads the union of the preference string, the file mirror and the
    /// legacy string list, healing the preference when the mirror is the
    /// only copy that survived.
    func load() -> Set<String> {
        var ids = Set<String>()

        if let jsonString = defaults.string(forKey: key),
           let data = jsonString.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            ids.formUnion(decoded)
        }
        if let mirrorURL, let data = try? Data(contentsOf: mirrorURL),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            ids.formUnion(decoded)
        }
        // Legacy string-list recovery (older builds stored a plain list).
        if let legacy = defaults.stringArray(forKey: "\(key).legacy") {
            ids.formUnion(legacy)
        }

        // Heal: if the preference lost the ids but the mirror kept them,
        // write them back so the next load doesn't depend on the mirror.
        if !ids.isEmpty {
            save(ids)
        }
        return ids
    }

    /// Writes to both the preference string and the file mirror.
    func save(_ ids: Set<String>) {
        let sorted = Array(ids).sorted()
        if let data = try? JSONEncoder().encode(sorted),
           let jsonString = String(data: data, encoding: .utf8) {
            defaults.set(jsonString, forKey: key)
        }
        if let mirrorURL, let data = try? JSONEncoder().encode(sorted) {
            try? data.write(to: mirrorURL, options: .atomic)
        }
    }
}

/// The JSON-file mirror for single-value settings (theme, sounds, tour
/// seen flag), matching the Flutter `SettingsMirror` that writes
/// `ui_settings.json`. One file, one JSON object of key → value.
final class SettingsMirror {
    private let fileURL: URL?

    init(fileName: String = "ui_settings.json") {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        self.fileURL = documents?.appendingPathComponent(fileName)
    }

    func readAll() -> [String: Any] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    func writeKey(_ key: String, _ value: Any) {
        var all = readAll()
        all[key] = value
        guard let fileURL,
              let data = try? JSONSerialization.data(withJSONObject: all, options: [.sortedKeys]) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
