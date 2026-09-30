//
//  SettingsView.swift
//  Downer
//
//  Created by Dumindu Sameendra on 2025-04-17.
//
import AppKit
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    // persisted tool paths
    @AppStorage("backgroundGlow") private var backgroundGlow = true
    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw = AppearanceMode.system.rawValue
    @ObservedObject private var deps = DependencyManager.shared

    var body: some View {
        ZStack {
            // fix title and colors as soon as it's available to edit
            WindowAccessor { window in
                MainActor.assumeIsolated { DownerWindowChrome.apply(to: window, title: "Settings") }
            }

            AmbientBackground()

            ScrollView {
                VStack(spacing: 14) {
                    appearanceGroup.appear(0)
                    shortcutGroup.appear(1)
                    requirementsGroup.appear(2)
                }
                .padding(16)
                .padding(.top, -4)
            }
            .scrollIndicators(.never)

            // drawn last so the scroll view's edge blur never sits on top of the title
            TitleBarRow(title: "Settings") { EmptyView() }
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .tint(Brand.red)
        .frame(width: 400, height: 405)
        .onAppear { deps.refresh() }
    }

    // MARK: Sections
    private var appearanceGroup: some View {
        OptionGroup(title: "Appearance") {
            HStack(spacing: 14) {
                Text("Theme")
                    .font(.system(size: 14))
                Spacer(minLength: 0)
                Picker("Theme", selection: $appearanceRaw) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
            }
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .frame(height: 50)
            .overlay(alignment: .bottom) { Divider().opacity(0.6).padding(.horizontal, 14) }
            .onChange(of: appearanceRaw) { _, new in AppearanceMode.apply(new) }

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Background glow")
                        .font(.system(size: 14))
                    Text("Soft colour behind the glass. Off uses a plain window.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Toggle("Background glow", isOn: $backgroundGlow.animation())
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .padding(.vertical, 8)
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .frame(minHeight: 58)
        }
    }

    private var shortcutGroup: some View {
        OptionGroup(title: "Global Shortcut") {
            HStack {
                Text("Open quick download")
                    .font(.system(size: 14))
                Spacer()
                KeyboardShortcuts.Recorder(for: .downloadShortcut)
            }
            .help("Opens the menu bar window from anywhere. A copied link is filled in for you.")
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(height: 46)
        }
    }

    private var requirementsGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            OptionGroup(title: "Requirements") {
                ForEach(Array(Tool.allCases.enumerated()), id: \.element) { index, tool in
                    requirementRow(tool, showsDivider: index < Tool.allCases.count - 1)
                }
            }
            requirementsFooter
        }
    }

    @ViewBuilder
    private var requirementsFooter: some View {
        let text: String? = {
            if let failure = deps.failure { return failure }
            if !deps.installing.isEmpty { return deps.log.isEmpty ? "Installing…" : deps.log }
            if deps.brewPath == nil && !deps.missing.isEmpty {
                return deps.missing.contains(where: { $0 != .ytDlp })
                    ? "ffmpeg needs Homebrew. yt-dlp can be installed without it."
                    : nil
            }
            return nil
        }()
        HStack(spacing: 8) {
            if let text {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(deps.failure == nil ? Color.secondary : Color.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if deps.brewPath == nil && deps.missing.contains(where: { $0 != .ytDlp }) {
                Spacer(minLength: 0)
                Button("Get Homebrew") { deps.openHomebrewSite() }
                    .buttonStyle(PillButtonStyle())
            }
        }
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private func requirementRow(_ tool: Tool, showsDivider: Bool) -> some View {
        let st = deps.status[tool]
        let installed = st?.isInstalled ?? false
        let busy = deps.isInstalling(tool)
        let binding = pathBinding(for: tool)

        HStack(spacing: 8) {
            Text(tool.title)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 58, alignment: .leading)

            HStack(spacing: 6) {
                Image(systemName: installed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(installed ? Color.green : Color.orange)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: installed)
                Text(statusText(installed: installed, version: st?.version, busy: busy))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contentTransition(.opacity)
                    .help(st?.path ?? "")
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 28)
            .background(Color.primary.opacity(0.08), in: Capsule())

            if busy {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 70)
                    .transition(.opacity)
            } else if installed {
                Button("Browse…") { choosePath(for: binding) }
                    .buttonStyle(PillButtonStyle())
            } else {
                Button("Install") { deps.install(tool) }
                    .buttonStyle(PrimaryPillButtonStyle())
                    .disabled(tool != .ytDlp && deps.brewPath == nil)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 44)
        .motion(value: installed)
        .motion(value: busy)
        .contextMenu {
            Button("Choose file…") { choosePath(for: binding) }
        }
        .overlay(alignment: .bottom) {
            if showsDivider { Divider().opacity(0.6).padding(.horizontal, 14) }
        }
    }

    private func statusText(installed: Bool, version: String?, busy: Bool) -> String {
        if busy { return "Installing…" }
        if !installed { return deps.hasCheckedOnce ? "Not found" : "Checking…" }
        return version.map { "Installed · \($0)" } ?? "Installed"
    }

    private func pathBinding(for tool: Tool) -> Binding<String> {
        Binding(
            get: { UserDefaults.standard.string(forKey: tool.defaultsKey) ?? tool.defaultPath },
            set: {
                UserDefaults.standard.set($0, forKey: tool.defaultsKey)
                deps.refresh()
            }
        )
    }

    private func choosePath(for binding: Binding<String>) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.message = "Choose the executable file"
        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                binding.wrappedValue = url.path
            }
        }
    }
}
