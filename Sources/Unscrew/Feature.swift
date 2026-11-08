import Foundation

/// The script's only argument.
enum FeatureAction: String {
    case apply
    case off
}

/// Trigger names understood by the `# on:` header key.
enum FeatureTrigger: String, CaseIterable {
    case launch
    case displays
    case wake
}

/// `# setting: <key> | <label> | <default>`, passed to the script as `UNSCREW_<KEY>`.
struct FeatureSetting: Equatable {
    let key: String
    let label: String
    let defaultValue: String
}

/// Header metadata of a feature script. Every key is optional.
struct FeatureHeader: Equatable {
    var name: String
    var description: String
    var triggers: Set<FeatureTrigger>
    var interval: TimeInterval
    var settings: [FeatureSetting]
}

/// One executable file in the features folder.
struct Feature: Identifiable, Equatable {
    let url: URL
    let filename: String
    let name: String
    let description: String
    let triggers: Set<FeatureTrigger>
    let interval: TimeInterval
    let settings: [FeatureSetting]

    var id: String { url.path }

    var defaultsKey: String { "enabled.\(filename)" }

    func settingKey(_ setting: FeatureSetting) -> String { "setting.\(filename).\(setting.key)" }
}

/// Reads the optional header comment lines of a script.
enum FeatureParser {
    static let headerLineLimit = 20

    static func header(_ text: String, fallbackName: String) -> FeatureHeader {
        var result = FeatureHeader(name: fallbackName, description: "", triggers: [], interval: 0, settings: [])
        for raw in text.split(whereSeparator: \.isNewline).prefix(headerLineLimit) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("#") else { continue }
            let body = line.dropFirst().trimmingCharacters(in: .whitespaces)
            guard let colon = body.firstIndex(of: ":") else { continue }
            let key = body[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = body[body.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "name":
                if !value.isEmpty { result.name = value }
            case "description":
                result.description = value
            case "on":
                for token in value.split(separator: ",") {
                    let name = token.trimmingCharacters(in: .whitespaces).lowercased()
                    if let trigger = FeatureTrigger(rawValue: name) { result.triggers.insert(trigger) }
                }
            case "interval":
                if let seconds = Double(value), seconds > 0 { result.interval = seconds }
            case "setting":
                if let setting = FeatureParser.setting(value) { result.settings.append(setting) }
            default:
                break
            }
        }
        return result
    }

    static let settingKeyChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_")

    static func setting(_ text: String) -> FeatureSetting? {
        let parts = text.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        let key = parts.first ?? ""
        guard !key.isEmpty, key.unicodeScalars.allSatisfy(settingKeyChars.contains) else { return nil }
        let label = parts.count > 1 && !parts[1].isEmpty ? parts[1] : key
        let defaultValue = parts.count > 2 ? parts[2] : ""
        return FeatureSetting(key: key, label: label, defaultValue: defaultValue)
    }
}

/// Outcome of one script run, shown in the settings window.
struct RunResult {
    let action: FeatureAction
    let date: Date
    let exitCode: Int32
    let output: String

    var statusText: String { exitCode == 0 ? "ok" : "exit \(exitCode)" }

    /// Last 3 non-empty output lines.
    var outputTail: String {
        let lines = output
            .split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return lines.suffix(3).joined(separator: "\n")
    }
}

/// `Unscrew --selftest`
enum Selftest {
    static func run() {
        let sample = """
        #!/bin/zsh
        # name: Menu bar auto-hide
        # description: Hide the menu bar while an external display is connected.
        # on: launch, displays, wake
        # interval: 300
        # Usage: menubar-autohide.sh apply|off
        echo hi
        """
        let full = FeatureParser.header(sample, fallbackName: "menubar-autohide")
        precondition(full.name == "Menu bar auto-hide", "name: got \"\(full.name)\"")
        precondition(
            full.description == "Hide the menu bar while an external display is connected.",
            "description: got \"\(full.description)\""
        )
        precondition(full.triggers == Set(FeatureTrigger.allCases), "triggers: got \(full.triggers)")
        precondition(full.interval == 300, "interval: got \(full.interval)")

        let bare = FeatureParser.header("#!/bin/bash\necho hi\n", fallbackName: "plain")
        precondition(bare.name == "plain", "default name: got \"\(bare.name)\"")
        precondition(bare.description.isEmpty, "default description: got \"\(bare.description)\"")
        precondition(bare.triggers.isEmpty, "default triggers: got \(bare.triggers)")
        precondition(bare.interval == 0, "default interval: got \(bare.interval)")

        let partial = FeatureParser.header("# on: wake, reboot\n# interval: soon\n", fallbackName: "t")
        precondition(partial.triggers == [.wake], "unknown trigger must be dropped: got \(partial.triggers)")
        precondition(partial.interval == 0, "bad interval must fall back to 0: got \(partial.interval)")

        let late = FeatureParser.header(Array(repeating: "# pad", count: 20).joined(separator: "\n") + "\n# name: Late\n", fallbackName: "early")
        precondition(late.name == "early", "headers past line 20 must be ignored: got \"\(late.name)\"")
        let lateSetting = FeatureParser.header(
            Array(repeating: "# pad", count: 20).joined(separator: "\n") + "\n# setting: late | Late | 1\n",
            fallbackName: "t"
        )
        precondition(lateSetting.settings.isEmpty, "settings past line 20 must be ignored: got \"\(lateSetting.settings)\"")

        let declared = FeatureParser.header("""
        #!/bin/zsh
        # setting: minutes | Quit after (minutes) | 2
        # setting: Bad Key | x | y
        # setting: keep | Keep running |
        """, fallbackName: "s")
        precondition(declared.settings.count == 2, "expected 2 settings, bad key dropped: got \(declared.settings)")
        precondition(
            declared.settings[0] == FeatureSetting(key: "minutes", label: "Quit after (minutes)", defaultValue: "2"),
            "first setting: got \(declared.settings[0])"
        )
        precondition(
            declared.settings[1] == FeatureSetting(key: "keep", label: "Keep running", defaultValue: ""),
            "second setting: got \(declared.settings[1])"
        )
        let badKeys = FeatureParser.header(
            "# setting: | x | y\n# setting: UPPER | x | y\n# setting: a-b | x | y\n# setting: ok_key9 | Ok | z\n",
            fallbackName: "k"
        )
        precondition(badKeys.settings.map(\.key) == ["ok_key9"], "invalid keys must be dropped: got \(badKeys.settings)")
        let noDefault = FeatureParser.header("# setting: only | Only\n", fallbackName: "d")
        precondition(noDefault.settings.map(\.defaultValue) == [""], "missing default must be \"\": got \(noDefault.settings)")

        precondition(bare.settings.isEmpty, "default settings: got \(bare.settings)")

        print("selftest ok")
    }
}
