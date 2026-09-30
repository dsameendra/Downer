//
//  DependencyManager.swift
//  Downer
//
//  Finds yt-dlp, ffmpeg and ffprobe, and installs them from Settings:
//  through Homebrew when it is present, or (yt-dlp only) by downloading the
//  official standalone release into Application Support.
//

import AppKit
import Foundation

enum Tool: String, CaseIterable, Identifiable {
    case ytDlp, ffmpeg, ffprobe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ytDlp: return "yt-dlp"
        case .ffmpeg: return "ffmpeg"
        case .ffprobe: return "ffprobe"
        }
    }

    /// The AppStorage key the download code already reads.
    var defaultsKey: String {
        switch self {
        case .ytDlp: return "ytDlpPath"
        case .ffmpeg: return "ffmpegPath"
        case .ffprobe: return "ffprobePath"
        }
    }

    var defaultPath: String { "/opt/homebrew/bin/" + title }

    /// ffprobe ships inside the ffmpeg formula, so both install together.
    var installGroup: Tool { self == .ytDlp ? .ytDlp : .ffmpeg }

    var brewFormula: String { self == .ytDlp ? "yt-dlp" : "ffmpeg" }
}

struct ToolStatus: Equatable {
    var path: String?
    var version: String?
    var isInstalled: Bool { path != nil }
}

enum InstallError: LocalizedError {
    case needsHomebrew
    case brewFailed(String)
    case download(String)

    var errorDescription: String? {
        switch self {
        case .needsHomebrew:
            return "ffmpeg is installed with Homebrew. Install Homebrew first, then try again."
        case .brewFailed(let detail):
            return "Homebrew could not finish the install. \(detail)"
        case .download(let detail):
            return "The download failed. \(detail)"
        }
    }
}

@MainActor
final class DependencyManager: ObservableObject {
    static let shared = DependencyManager()

    @Published private(set) var status: [Tool: ToolStatus] = [:]
    @Published private(set) var installing: Set<Tool> = []
    @Published private(set) var log = ""
    @Published private(set) var failure: String?

    private var activationObserver: NSObjectProtocol?

    private init() {
        refresh()
        // pick up installs done outside the app when the user comes back to it
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: Queries
    var missing: [Tool] {
        Tool.allCases.filter { status[$0]?.isInstalled == false }
    }

    var hasCheckedOnce: Bool { !status.isEmpty }

    var brewPath: String? {
        #if DOWNER_TEST_NO_BREW
            return nil  // lets tests exercise the no-Homebrew install path
        #endif
        return ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    func isInstalling(_ tool: Tool) -> Bool {
        installing.contains(tool.installGroup)
    }

    // MARK: Detection
    func refresh() {
        Task {
            var result: [Tool: ToolStatus] = [:]
            for tool in Tool.allCases {
                let path = await Task.detached { Self.locate(tool) }.value
                var version: String?
                if let path {
                    version = await Task.detached { Self.version(of: tool, at: path) }.value
                    // keep the download code pointed at a working binary
                    if path != Self.configuredPath(tool) {
                        UserDefaults.standard.set(path, forKey: tool.defaultsKey)
                    }
                }
                result[tool] = ToolStatus(path: path, version: version)
            }
            status = result
        }
    }

    nonisolated static var managedBinDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downer/bin", isDirectory: true)
    }

    nonisolated static func configuredPath(_ tool: Tool) -> String {
        UserDefaults.standard.string(forKey: tool.defaultsKey) ?? tool.defaultPath
    }

    nonisolated private static func locate(_ tool: Tool) -> String? {
        let fm = FileManager.default
        let configured = configuredPath(tool)
        if fm.isExecutableFile(atPath: configured) { return configured }
        let dirs = [
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
            managedBinDirectory.path,
        ]
        return dirs.map { $0 + "/" + tool.title }.first { fm.isExecutableFile(atPath: $0) }
    }

    nonisolated private static func version(of tool: Tool, at path: String) -> String? {
        let args = tool == .ytDlp ? ["--version"] : ["-version"]
        guard let out = capture(path, args) else { return nil }
        let first = out.split(separator: "\n").first.map(String.init) ?? ""
        if tool == .ytDlp { return first.trimmingCharacters(in: .whitespaces) }
        // "ffmpeg version 7.1 Copyright …"
        let parts = first.split(separator: " ")
        return parts.count > 2 ? String(parts[2]) : nil
    }

    nonisolated private static func capture(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    // MARK: Install
    func install(_ tool: Tool) {
        let group = tool.installGroup
        guard !installing.contains(group) else { return }
        installing.insert(group)
        failure = nil
        log = "Starting…"

        Task {
            do {
                if let brew = brewPath {
                    try await runBrew(brew, formula: group.brewFormula)
                } else if group == .ytDlp {
                    try await downloadYtDlp()
                } else {
                    throw InstallError.needsHomebrew
                }
            } catch {
                failure = error.localizedDescription
            }
            installing.remove(group)
            log = ""
            refresh()
        }
    }

    func openHomebrewSite() {
        if let url = URL(string: "https://brew.sh") { NSWorkspace.shared.open(url) }
    }

    private func setLog(_ text: String) {
        let line = text
            .split(whereSeparator: \.isNewline)
            .last
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        if !line.isEmpty { log = String(line.prefix(90)) }
    }

    private func runBrew(_ brew: String, formula: String) async throws {
        try await withCheckedThrowingContinuation {
            (cont: CheckedContinuation<Void, Error>) in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: brew)
            proc.arguments = ["install", formula]
            var env = ProcessInfo.processInfo.environment
            env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            env["HOMEBREW_NO_ENV_HINTS"] = "1"
            env["NONINTERACTIVE"] = "1"
            proc.environment = env

            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
                let data = h.availableData
                guard !data.isEmpty else {
                    h.readabilityHandler = nil
                    return
                }
                guard let s = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor in
                    self?.setLog(s)
                }
            }
            proc.terminationHandler = { p in
                pipe.fileHandleForReading.readabilityHandler = nil
                if p.terminationStatus == 0 {
                    cont.resume()
                } else {
                    cont.resume(throwing: InstallError.brewFailed("(exit \(p.terminationStatus))"))
                }
            }
            do { try proc.run() } catch {
                cont.resume(throwing: InstallError.brewFailed(error.localizedDescription))
            }
        }
    }

    private func downloadYtDlp() async throws {
        setLog("Downloading yt-dlp…")
        guard
            let url = URL(
                string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")
        else { return }
        do {
            let (tmp, response) = try await URLSession.shared.download(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw InstallError.download("GitHub answered \(http.statusCode).")
            }
            let fm = FileManager.default
            try fm.createDirectory(at: Self.managedBinDirectory, withIntermediateDirectories: true)
            let dest = Self.managedBinDirectory.appendingPathComponent("yt-dlp")
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.moveItem(at: tmp, to: dest)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
        } catch let error as InstallError {
            throw error
        } catch {
            throw InstallError.download(error.localizedDescription)
        }
    }
}
