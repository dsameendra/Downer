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
    /// Every file the last run produced (a playlist makes several).
    @Published private(set) var lastFiles: [URL] = []
    /// Set only while or after a playlist run. Single videos never set it.
    @Published private(set) var playlist: PlaylistProgress?
    /// True when the last run failed, so the menu bar icon can ask for attention.
    @Published private(set) var hadError = false

    private var process: Process?
    private var idleTask: Task<Void, Never>?
    private var lastErrorLine: String?
    private var wasCancelled = false
    private var pathFile: URL?
    private var tracker = PlaylistTracker()
    private var lastURL: String?
    private var retryMap: [Int]?

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
        start(url: rawURL, retrying: nil)
    }

    /// Download again only the failed items of the last playlist.
    func retryFailed() {
        guard let url = lastURL, let failed = playlist?.failed.map(\.id), !failed.isEmpty else { return }
        start(url: url, retrying: failed)
    }

    /// Clear the playlist summary once a run is over.
    func dismissPlaylist() {
        guard !isDownloading else { return }
        playlist = nil
        hadError = false
        status = "Idle"
    }

    private func start(url rawURL: String, retrying: [Int]?) {
        let url = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, !isDownloading else { return }
        idleTask?.cancel()
        hadError = false

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
        if let retrying { args += ["--playlist-items", retrying.map(String.init).joined(separator: ",")] }
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
        lastFiles = []
        lastURL = url
        retryMap = retrying
        tracker = retrying == nil ? PlaylistTracker() : PlaylistTracker(retrying: retrying, keeping: playlist)
        if retrying == nil { playlist = nil }
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
        let files = lastFiles.isEmpty ? lastFile.map { [$0] } ?? [] : lastFiles
        if files.isEmpty {
            NSWorkspace.shared.open(destinationFolder)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(files)
        }
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

        let hadPlaylist = playlist != nil
        tracker.consume(line)
        if tracker.progress != playlist { playlist = tracker.progress }
        if !hadPlaylist, playlist != nil, let url = lastURL { fetchTitles(for: url) }

        // "[download]  42.3% of  120.00MiB at  3.20MiB/s ETA 00:24"
        if line.hasPrefix("[download]"), let pct = Self.percent(in: line) {
            if let playlist {
                progress = playlist.overall
                let current = playlist.current.map { "Item \($0) of \(playlist.total)" } ?? "Playlist"
                var text = "\(current) · \(Int(pct.rounded()))%"
                if let speed = playlist.speed { text += " · \(speed)" }
                status = text
            } else {
                progress = pct / 100
                var text = "Downloading \(Int(pct.rounded()))%"
                if let speed = Self.value(after: " at ", in: line) { text += " · \(speed)" }
                if let eta = Self.value(after: "ETA ", in: line) { text += " · \(eta) left" }
                status = text
            }
            return
        }
        // Only yt-dlp's own tagged lines are worth showing; ffmpeg chatter is not.
        guard line.hasPrefix("[") else { return }
        if line.hasPrefix("[Merger]") || line.hasPrefix("[VideoRemuxer]") {
            if playlist == nil { progress = nil }
            status = "Merging…"
        } else if line.hasPrefix("[ExtractAudio]") {
            if playlist == nil { progress = nil }
            status = "Converting audio…"
        } else if line.hasPrefix("[download] Downloading item"), let playlist, let current = playlist.current {
            progress = playlist.overall
            status = "Item \(current) of \(playlist.total)"
        } else if line.hasPrefix("[download]") || line.contains("%(filepath)s") {
            return
        } else if line.hasPrefix("Deleting original file") {
            status = "Finishing…"
        } else if playlist == nil {
            status = line
        }
    }

    /// Ask yt-dlp for the playlist's titles so every queued row has a name.
    private func fetchTitles(for url: String) {
        let ytDlpPath = string(Tool.ytDlp.defaultsKey, Tool.ytDlp.defaultPath)
        let only = retryMap
        Task.detached { [weak self] in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: ytDlpPath)
            var args = ["--flat-playlist", "--print", "%(title)s", "--no-warnings"]
            if let only { args += ["--playlist-items", only.map(String.init).joined(separator: ",")] }
            args.append(url)
            proc.arguments = args
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            guard (try? proc.run()) != nil else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            let titles = (String(data: data, encoding: .utf8) ?? "")
                .split(whereSeparator: \.isNewline).map(String.init)
            guard !titles.isEmpty else { return }
            await self?.applyTitles(titles)
        }
    }

    private func applyTitles(_ titles: [String]) {
        tracker.setTitles(titles)
        playlist = tracker.progress
    }

    private func finished(code: Int32) {
        process = nil
        isDownloading = false
        progress = nil
        tracker.finish(exitCode: code, cancelled: wasCancelled)
        if tracker.progress != nil { playlist = tracker.progress }
        let files = pathFile
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }?
            .split(whereSeparator: \.isNewline).map { URL(fileURLWithPath: String($0)) } ?? []
        defer { if let pathFile { try? FileManager.default.removeItem(at: pathFile) } }
        if !files.isEmpty { lastFiles = (retryMap == nil ? [] : lastFiles) + files }

        if wasCancelled {
            status = "Download cancelled."
        } else if let playlist {
            let failed = playlist.failed.count
            lastFile = lastFiles.last
            if failed == 0 && code == 0 {
                status = "Playlist completed."
                completions += 1
            } else if playlist.doneCount == 0 {
                hadError = true
                status = "Download failed (code \(code))."
                return
            } else {
                hadError = failed > 0
                status = "\(playlist.doneCount) of \(playlist.total) downloaded · \(failed) failed"
                if failed == 0 { completions += 1 }
                return  // keep the summary on screen
            }
        } else if code == 0 {
            status = "Download completed."
            completions += 1
            lastFile = files.last
            lastFiles = files
        } else {
            let detail = lastErrorLine.map { "\n" + String($0.prefix(140)) } ?? ""
            status = "Download failed (code \(code))." + detail
            hadError = true
            return  // keep the error on screen until the next attempt
        }
        scheduleIdle()
    }

    private func fail(_ message: String) {
        hadError = true
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
