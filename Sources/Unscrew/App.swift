import AppKit
import SwiftUI

// State lives in FeatureStore: the @State macro plugin is missing from the Command Line Tools.

struct UnscrewApp: App {
    let store: FeatureStore

    init() {
        store = .shared
        store.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store)
        } label: {
            Image(nsImage: menuBarIcon)
        }
        .menuBarExtraStyle(.menu)

        Window("Unscrew Settings", id: "settings") {
            SettingsView(store: store)
                .onAppear { store.reload() }
        }
        .defaultSize(width: 520, height: 400)
    }
}

// MARK: - Menu bar

private struct MenuContent: View {
    @ObservedObject var store: FeatureStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if store.features.isEmpty {
            Text("No feature scripts")
        } else {
            ForEach(store.features) { feature in
                Toggle(feature.name, isOn: store.binding(for: feature))
            }
        }

        Divider()
        Button("Settings…") {
            openWindow(id: "settings")
            NSApp.activate()
        }
        Button("Open Features Folder") { store.openFeaturesFolder() }
        Button("Reload Features") { store.reload() }

        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }
}

// MARK: - Settings window

private struct SettingsView: View {
    @ObservedObject var store: FeatureStore

    var body: some View {
        VStack(spacing: 0) {
            if store.features.isEmpty {
                VStack(spacing: 6) {
                    Text("No feature scripts")
                        .font(.headline)
                    Text("Put executable scripts in:\n\(store.folderURL.path)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(store.features) { feature in
                        FeatureRow(
                            name: feature.name,
                            detail: feature.description,
                            schedule: scheduleText(feature),
                            result: store.results[feature.id],
                            isOn: store.binding(for: feature),
                            feature: feature,
                            store: store
                        )
                    }
                }
            }

            Divider()
            SettingsFooter(store: store)
        }
        .frame(minWidth: 520, minHeight: 400)
    }

    private func scheduleText(_ feature: Feature) -> String {
        var parts: [String] = []
        if !feature.triggers.isEmpty {
            parts.append("on: " + feature.triggers.map(\.rawValue).sorted().joined(separator: ", "))
        }
        if feature.interval > 0 {
            parts.append("every \(Int(feature.interval)) s")
        }
        return parts.joined(separator: "  ·  ")
    }
}

private struct FeatureRow: View {
    let name: String
    let detail: String
    let schedule: String
    let result: RunResult?
    var isOn: Binding<Bool>
    let feature: Feature
    @ObservedObject var store: FeatureStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(name, isOn: isOn)

            if !detail.isEmpty {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !feature.settings.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(feature.settings, id: \.key) { setting in
                            HStack(spacing: 6) {
                                Text(setting.label)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                TextField(
                                    setting.defaultValue.isEmpty ? "macOS default" : setting.defaultValue,
                                    text: store.binding(for: feature, setting)
                                )
                                .frame(width: 160)
                                .onSubmit { reapply() }
                            }
                        }
                    }
                    Button("Reset to default") { store.resetSettings(feature) }
                        .controlSize(.small)
                }
                .padding(.top, 2)
            }

            if !schedule.isEmpty {
                Text(schedule)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let result {
                Text("last run \(result.date.formatted(date: .abbreviated, time: .shortened)) · \(result.action.rawValue) · \(result.statusText)")
                    .font(.caption)
                    .foregroundStyle(result.exitCode == 0 ? Color.secondary : Color.red)

                if !result.outputTail.isEmpty {
                    Text(result.outputTail)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            Color(nsColor: .textBackgroundColor).opacity(0.6),
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                }
            } else {
                Text("not run yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func reapply() {
        guard store.isEnabled(feature) else { return }
        store.run(feature, .apply)
    }
}

private struct SettingsFooter: View {
    @ObservedObject var store: FeatureStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !store.loginError.isEmpty {
                Text(store.loginError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            HStack {
                Toggle("Launch at login", isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { store.setLaunchAtLogin($0) }
                ))
                Spacer()
                Button("Open Features Folder") { store.openFeaturesFolder() }
                Button("Reload") { store.reload() }
            }
        }
        .padding(10)
    }
}

// MARK: - Menu bar icon

/// Ring around a screw head, as a template image so macOS tints it.
let menuBarIcon: NSImage = {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
        let c = NSPoint(x: rect.midX, y: rect.midY)
        NSColor.black.set()

        let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
        ring.lineWidth = 1.6
        ring.stroke()

        NSBezierPath(ovalIn: NSRect(x: c.x - 5.5, y: c.y - 5.5, width: 11, height: 11)).fill()

        // Cut the Phillips cross out of the head.
        NSGraphicsContext.current?.compositingOperation = .clear
        for angle in [20.0, 110.0] {
            let slot = NSBezierPath(roundedRect: NSRect(x: c.x - 3.6, y: c.y - 0.8, width: 7.2, height: 1.6),
                                    xRadius: 0.8, yRadius: 0.8)
            var t = AffineTransform(translationByX: c.x, byY: c.y)
            t.rotate(byDegrees: angle)
            t.translate(x: -c.x, y: -c.y)
            slot.transform(using: t)
            slot.fill()
        }
        return true
    }
    image.isTemplate = true
    return image
}()
