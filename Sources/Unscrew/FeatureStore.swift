import AppKit
import Foundation
import ServiceManagement
import SwiftUI

/// Scans the features folder, runs scripts and holds the UI state. Main thread only.
final class FeatureStore: ObservableObject {
    @Published private(set) var features: [Feature] = []
    @Published private(set) var enabledIDs: Set<String> = []
    @Published private(set) var results: [String: RunResult] = [:]
    /// Stored setting values by `Feature.settingKey`; missing means the header default.
    @Published private(set) var settingValues: [String: String] = [:]
    @Published private(set) var launchAtLogin = false
    @Published private(set) var loginError = ""

    static let shared = FeatureStore()

    let folderURL: URL
    private let defaults: UserDefaults

    private var running: Set<String> = []       // main thread only
    private var timers: [String: Timer] = [:]   // main thread only
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var pendingDisplays: DispatchWorkItem?
    private var started = false

    static let runTimeout: TimeInterval = 30
    static let displaysDebounce: TimeInterval = 2
    static let maxOutputBytes = 64 * 1024

    static var featuresFolder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return support
            .appendingPathComponent("Unscrew", isDirectory: true)
            .appendingPathComponent("features", isDirectory: true)
    }

    init(folderURL: URL = FeatureStore.featuresFolder, defaults: UserDefaults = .standard) {
        self.folderURL = folderURL
        self.defaults = defaults
        installBundledFeatures()
        reload()
    }

    /// Copies the scripts shipped in the app into the features folder, never overwriting.
    private func installBundledFeatures() {
        let fm = FileManager.default
        guard let bundled = Bundle.main.resourceURL?.appendingPathComponent("features"),
              let names = try? fm.contentsOfDirectory(atPath: bundled.path) else { return }
        try? fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
        for name in names where !fm.fileExists(atPath: folderURL.appendingPathComponent(name).path) {
            try? fm.copyItem(at: bundled.appendingPathComponent(name), to: folderURL.appendingPathComponent(name))
        }
    }

    deinit {
        for (center, observer) in observers { center.removeObserver(observer) }
        for timer in timers.values { timer.invalidate() }
    }

    // MARK: - Scanning

    /// Re-read the features folder and rebuild the interval timers.
    func reload() {
        let fm = FileManager.default
        try? fm.createDirectory(at: folderURL, withIntermediateDirectories: true)

        var found: [Feature] = []
        let names = ((try? fm.contentsOfDirectory(atPath: folderURL.path)) ?? []).sorted()
        for name in names {
            if name.hasPrefix(".") { continue }
            let url = folderURL.appendingPathComponent(name)
            var isDirectory = ObjCBool(false)
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
            guard fm.isExecutableFile(atPath: url.path) else { continue }
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let header = FeatureParser.header(text, fallbackName: (name as NSString).deletingPathExtension)
            found.append(
                Feature(
                    url: url,
                    filename: name,
                    name: header.name,
                    description: header.description,
                    triggers: header.triggers,
                    interval: header.interval,
                    settings: header.settings
                )
            )
        }

        features = found
        enabledIDs = Set(found.filter { defaults.bool(forKey: $0.defaultsKey) }.map(\.id))

        var values: [String: String] = [:]
        for feature in found {
            for setting in feature.settings {
                let key = feature.settingKey(setting)
                if let stored = defaults.string(forKey: key) { values[key] = stored }
            }
        }
        settingValues = values
        refreshLoginStatus()
        rebuildTimers()
    }

    // MARK: - Login item

    func refreshLoginStatus() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = ""
        } catch {
            loginError = "Launch at login failed: \(error.localizedDescription)"
        }
        refreshLoginStatus()
    }

    func openFeaturesFolder() {
        NSWorkspace.shared.open(folderURL)
    }

    // MARK: - Enabled state

    func isEnabled(_ feature: Feature) -> Bool { enabledIDs.contains(feature.id) }

    func setEnabled(_ feature: Feature, _ enabled: Bool) {
        defaults.set(enabled, forKey: feature.defaultsKey)
        if enabled { enabledIDs.insert(feature.id) } else { enabledIDs.remove(feature.id) }
        rebuildTimers()
        run(feature, enabled ? .apply : .off)
    }

    func binding(for feature: Feature) -> Binding<Bool> {
        Binding(
            get: { self.isEnabled(feature) },
            set: { self.setEnabled(feature, $0) }
        )
    }

    // MARK: - Settings

    func value(_ feature: Feature, _ setting: FeatureSetting) -> String {
        settingValues[feature.settingKey(setting)] ?? setting.defaultValue
    }

    func setValue(_ feature: Feature, _ setting: FeatureSetting, _ value: String) {
        let key = feature.settingKey(setting)
        defaults.set(value, forKey: key)
        settingValues[key] = value
    }

    func resetSettings(_ feature: Feature) {
        for setting in feature.settings {
            let key = feature.settingKey(setting)
            defaults.removeObject(forKey: key)
            settingValues.removeValue(forKey: key)
        }
        if isEnabled(feature) { run(feature, .apply) }
    }

    func binding(for feature: Feature, _ setting: FeatureSetting) -> Binding<String> {
        Binding(
            get: { self.value(feature, setting) },
            set: { self.setValue(feature, setting, $0) }
        )
    }

    /// Parent environment, `UNSCREW_APP` (the app bundle) and `UNSCREW_<KEY>` per setting.
    private func environment(for feature: Feature) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["UNSCREW_APP"] = Bundle.main.bundlePath
        for setting in feature.settings {
            env["UNSCREW_" + setting.key.uppercased()] = value(feature, setting)
        }
        return env
    }

    // MARK: - Triggers

    /// Fires the launch trigger and starts watching displays and wake.
    func start() {
        guard !started else { return }
        started = true

        fire(trigger: .launch)

        observers.append((NotificationCenter.default, NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.displaysChanged()
        }))
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append((workspaceCenter, workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.fire(trigger: .wake)
        }))
    }

    private func displaysChanged() {
        pendingDisplays?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.fire(trigger: .displays) }
        pendingDisplays = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.displaysDebounce, execute: work)
    }

    private func fire(trigger: FeatureTrigger) {
        for feature in features where isEnabled(feature) && feature.triggers.contains(trigger) {
            run(feature, .apply)
        }
    }

    private func rebuildTimers() {
        for timer in timers.values { timer.invalidate() }
        timers.removeAll()
        for feature in features where isEnabled(feature) && feature.interval > 0 {
            let timer = Timer(timeInterval: feature.interval, repeats: true) { [weak self] _ in
                self?.run(feature, .apply)
            }
            RunLoop.main.add(timer, forMode: .common)
            timers[feature.id] = timer
        }
    }

    // MARK: - Running

    /// Runs `<script> apply|off`, skipping if that feature is still running.
    func run(_ feature: Feature, _ action: FeatureAction) {
        guard !running.contains(feature.id) else { return }
        running.insert(feature.id)
        let url = feature.url
        let environment = environment(for: feature)
        DispatchQueue.global(qos: .utility).async {
            let result = FeatureStore.execute(url: url, action: action, environment: environment)
            DispatchQueue.main.async {
                self.running.remove(feature.id)
                self.results[feature.id] = result
            }
        }
    }

    /// Blocks the calling (background) queue until the script exits or is killed.
    private static func execute(url: URL, action: FeatureAction, environment: [String: String]) -> RunResult {
        let started = Date()
        let process = Process()
        process.executableURL = url
        process.arguments = [action.rawValue]
        process.environment = environment
        process.currentDirectoryURL = url.deletingLastPathComponent()
        process.standardInput = FileHandle.nullDevice

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        let stdout = PipeCollector(handle: outPipe.fileHandleForReading, limit: maxOutputBytes)
        let stderr = PipeCollector(handle: errPipe.fileHandleForReading, limit: maxOutputBytes)
        stdout.start()
        stderr.start()

        do {
            try process.run()
        } catch {
            _ = stdout.finish(timeout: 0)
            _ = stderr.finish(timeout: 0)
            let reason = (error as NSError).localizedDescription
            return RunResult(action: action, date: started, exitCode: -1, output: "cannot run script: \(reason)")
        }

        // SIGTERM after the timeout, SIGKILL 3 s later.
        let overrun = Flag(false)
        let watchdog = DispatchWorkItem {
            guard process.isRunning else { return }
            overrun.set()
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + runTimeout, execute: watchdog)

        process.waitUntilExit()
        watchdog.cancel()

        // Bounded wait: a background child may still hold the pipes open.
        let outData = stdout.finish(timeout: 1)
        let errData = stderr.finish(timeout: 1)

        var text = String(decoding: outData, as: UTF8.self)
        let errText = String(decoding: errData, as: UTF8.self)
        if !errText.isEmpty {
            text += text.isEmpty ? errText : "\n" + errText
        }
        if overrun.isSet && process.terminationReason == .uncaughtSignal {
            text += "\nkilled after \(Int(runTimeout)) s timeout"
        }
        return RunResult(
            action: action,
            date: started,
            exitCode: process.terminationStatus,
            output: text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

private final class Flag {
    private let lock = NSLock()
    private var flag = false

    init(_ flag: Bool) { self.flag = flag }

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }

    func set() {
        lock.lock()
        flag = true
        lock.unlock()
    }
}

/// Collects a pipe's output up to `limit` bytes without blocking.
private final class PipeCollector {
    private let handle: FileHandle
    private let limit: Int
    private let lock = NSLock()
    private var data = Data()
    private let eof = DispatchSemaphore(value: 0)

    init(handle: FileHandle, limit: Int) {
        self.handle = handle
        self.limit = limit
    }

    func start() {
        handle.readabilityHandler = { [self] source in
            let chunk = source.availableData
            if chunk.isEmpty {
                source.readabilityHandler = nil
                eof.signal()
                return
            }
            lock.lock()
            if data.count < limit { data.append(chunk) }
            lock.unlock()
        }
    }

    func finish(timeout: TimeInterval) -> Data {
        if timeout > 0 { _ = eof.wait(timeout: .now() + timeout) }
        handle.readabilityHandler = nil
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
