//
//  DownloadManager.swift
//  Downer
//
//  One downloader shared by the main window and the menu bar popover, so both
//  always show the same state. Runs yt-dlp with an argument list (no shell),
//  and turns its output into a status line and a real progress value.
//

import AppKit
import Foundation

@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var status = "Idle"
    @Published private(set) var isDownloading = false
    /// 0...1 while yt-dlp reports a percentage, nil while it is preparing or merging.
    @Published private(set) var progress: Double?
    /// Increments on every successful download; views use it to celebrate once.
    @Published private(set) var completions = 0
    /// The file the last successful download produced, for "Show in Finder".
    @Published private(set) var lastFile: URL?

    private var process: Process?
    private var idleTask: Task<Void, Never>?
    private var lastErrorLine: String?
    private var wasCancelled = false
    private var pathFile: URL?

    private init() {}

    // MARK: Settings snapshot
    private var defaults: UserDefaults { .standard }

    private func string(_ key: String, _ fallback: String) -> String {
        defaults.string(forKey: key) ?? fallback
    }

    private var downloadType: DownloadType {
        DownloadType(rawValue: string("downloadType", DownloadType.both.rawValue)) ?? .both
    }

    private var destinationFolder: URL {
        let fallback =
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
            ?? NSHomeDirectory()
        return URL(fileURLWithPath: string("destinationFolder", fallback))
    }

    // MARK: Control
    func start(url rawURL: String) {
        let url = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, !isDownloading else { return }
        idleTask?.cancel()

        let fm = FileManager.default
        let ytDlp = Tool.ytDlp
        let ytDlpPath = string(ytDlp.defaultsKey, ytDlp.defaultPath)
        let ffmpegPath = string(Tool.ffmpeg.defaultsKey, Tool.ffmpeg.defaultPath)
        let ffprobePath = string(Tool.ffprobe.defaultsKey, Tool.ffprobe.defaultPath)

        guard fm.fileExists(atPath: destinationFolder.path) else {
            fail("Destination folder not found.")
            return
        }
        guard fm.isExecutableFile(atPath: ytDlpPath) else {
            fail("yt‑dlp not found.\nInstall it in Settings → Requirements.")
            return
        }
        guard fm.isExecutableFile(atPath: ffmpegPath), fm.isExecutableFile(atPath: ffprobePath)
        else {
            fail("ffmpeg / ffprobe not found.\nInstall them in Settings → Requirements.")
            return
        }

        var args = formatArguments()
        let pathFile = fm.temporaryDirectory.appendingPathComponent("downer-\(UUID().uuidString).txt")
        self.pathFile = pathFile
        args += ["--print-to-file", "after_move:filepath", pathFile.path]
        args += ["--newline", "--ffmpeg-location", (ffmpegPath as NSString).deletingLastPathComponent]
        args.append(url)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ytDlpPath)
        proc.arguments = args
        proc.currentDirectoryURL = destinationFolder
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\((ffmpegPath as NSString).deletingLastPathComponent):" + (env["PATH"] ?? "")
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        let buffer = LineBuffer()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else {
                h.readabilityHandler = nil
                return
            }
            guard let chunk = String(data: data, encoding: .utf8) else { return }
            let complete = buffer.append(chunk)
            guard !complete.isEmpty else { return }
            Task { @MainActor in
                for line in complete { self?.handle(line: line) }
            }
        }
        proc.terminationHandler = { [weak self] p in
            pipe.fileHandleForReading.readabilityHandler = nil
            let code = p.terminationStatus
            Task { @MainActor in self?.finished(code: code) }
        }

        wasCancelled = false
        lastFile = nil
        lastErrorLine = nil
        progress = nil
        status = "Starting download…"
        isDownloading = true
        process = proc

        do {
            try proc.run()
        } catch {
            process = nil
            fail("Could not start yt‑dlp: \(error.localizedDescription)")
        }
    }

    func revealLastFile() {
        guard let lastFile else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastFile])
    }

    func cancel() {
        guard isDownloading else { return }
        wasCancelled = true
        process?.terminate()
    }

    // MARK: Arguments
    private func numericAbr(_ quality: String) -> Int? {
        Int(quality.replacingOccurrences(of: "k", with: ""))
    }

    private func formatArguments() -> [String] {
        let resolution = string("selectedResolution", "1080")
        let container = string("selectedVideoFormat", "mp4")
        let quality = string("selectedAudioQuality", "source")
        let audioFormat = string("selectedAudioFormat", "opus")

        let audioFilter: String = {
            if let abr = numericAbr(quality) { return "bestaudio[abr<=\(abr)][vcodec=none]" }
            return "bestaudio"
        }()

        switch downloadType {
        case .audio:
            var args = ["-f", audioFilter]
            if audioFormat != "source" {  // transcode only if asked
                args += ["--extract-audio", "--audio-format", audioFormat]
                if let abr = numericAbr(quality), abr <= 160 {
                    args += ["--audio-quality", quality]
                }
            }
            return args
        case .video:
            return ["-f", "bestvideo[height<=\(resolution)][acodec=none]", "--remux-video", container]
        case .both:
            return [
                "-f", "bestvideo[height<=\(resolution)]+\(audioFilter)",
                "--merge-output-format", container,
            ]
        }
    }

    // MARK: Output
    private func handle(line raw: String) {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("ERROR") { lastErrorLine = line }

        // "[download]  42.3% of  120.00MiB at  3.20MiB/s ETA 00:24"
        if line.hasPrefix("[download]"), let pct = Self.percent(in: line) {
            progress = pct / 100
            var text = "Downloading \(Int(pct.rounded()))%"
            if let speed = Self.value(after: " at ", in: line) { text += " · \(speed)" }
            if let eta = Self.value(after: "ETA ", in: line) { text += " · \(eta) left" }
            status = text
            return
        }
        if line.hasPrefix("[Merger]") || line.hasPrefix("[VideoRemuxer]") {
            progress = nil
            status = "Merging…"
        } else if line.hasPrefix("[ExtractAudio]") {
            progress = nil
            status = "Converting audio…"
        } else if line.hasPrefix("Deleting original file") {
            status = "Finishing…"
        } else if !line.hasPrefix("[download]") && !line.contains("%(filepath)s") {
            status = line
        }
    }

    private func finished(code: Int32) {
        process = nil
        isDownloading = false
        progress = nil
        defer { if let pathFile { try? FileManager.default.removeItem(at: pathFile) } }
        if wasCancelled {
            status = "Download cancelled."
        } else if code == 0 {
            status = "Download completed."
            completions += 1
            lastFile = pathFile
                .flatMap { try? String(contentsOf: $0, encoding: .utf8) }?
                .split(whereSeparator: \.isNewline).last
                .map { URL(fileURLWithPath: String($0)) }
        } else {
            let detail = lastErrorLine.map { "\n" + String($0.prefix(140)) } ?? ""
            status = "Download failed (code \(code))." + detail
            return  // keep the error on screen until the next attempt
        }
        scheduleIdle()
    }

    private func fail(_ message: String) {
        status = message
        isDownloading = false
        progress = nil
    }

    /// Return to "Idle" a little while after a finished, failed or cancelled run.
    private func scheduleIdle() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.resetIfIdle()
        }
    }

    private func resetIfIdle() {
        if !isDownloading { status = "Idle" }
    }

    nonisolated private static func percent(in line: String) -> Double? {
        guard let r = line.range(of: #"(\d+(?:\.\d+)?)%"#, options: .regularExpression) else {
            return nil
        }
        return Double(line[r].dropLast())
    }

    nonisolated private static func value(after marker: String, in line: String) -> String? {
        guard let r = line.range(of: marker) else { return nil }
        let rest = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
        return rest.split(separator: " ").first.map(String.init)
    }
}

/// Collects pipe output and hands back only complete lines (yt-dlp separates
/// progress updates with \r or \n). Used from one readability handler at a time.
private final class LineBuffer: @unchecked Sendable {
    private var pending = ""

    func append(_ chunk: String) -> [String] {
        pending += chunk
        var parts = pending.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
        pending = parts.removeLast()
        return parts.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}
