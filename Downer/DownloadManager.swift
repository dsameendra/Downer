//
//  DownloadManager.swift
//  Downer
//
//  The download queue, shared by the main window and the menu bar popover.
//  Links (single videos or playlists, in any mix) are added at any time; they
//  are looked up, then downloaded one after another by yt-dlp, run with an
//  argument list (no shell). Output becomes per-job and per-video progress.
//

import AppKit
import Foundation

@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var jobs: [DownloadJob] = []
    @Published private(set) var status = "Idle"
    /// Increments each time a job finishes cleanly; views use it to celebrate once.
    @Published private(set) var completions = 0
    /// True when something in the queue failed, so the menu bar icon can ask for attention.
    @Published private(set) var hadError = false

    private var process: Process?
    private var runningID: UUID?
    private var tracker = PlaylistTracker()
    private var pathFile: URL?
    private var lastErrorLine: String?
    private var wasCancelled = false
    private var stopQueue = false
    private var idleTask: Task<Void, Never>?

    // look-ups run one at a time so pasting twenty links does not start twenty yt-dlps
    private var toResolve: [UUID] = []
    private var resolving = false

    private init() {}

    #if DEBUG
        /// Previews and screenshots only: show a queue without running anything.
        static var previewTrayOpen = false
        func loadPreview(jobs: [DownloadJob], status: String) {
            self.jobs = jobs
            self.status = status
        }
    #else
        static let previewTrayOpen = false
    #endif

    // MARK: Derived state
    var summary: QueueSummary { QueueSummary(jobs: jobs) }
    var isDownloading: Bool { runningID != nil }
    /// Something is running or waiting.
    var isActive: Bool { jobs.contains { $0.state == .running || $0.state == .queued } }
    /// A queue tray is warranted: more than one link, or a playlist.
    var needsTray: Bool { jobs.count > 1 || jobs.first?.isPlaylist == true }
    var runningJob: DownloadJob? { jobs.first { $0.id == runningID } }

    /// 0…1 across the whole queue while it is active.
    var progress: Double? { isActive ? summary.overall : nil }

    var lastFiles: [URL] { jobs.flatMap(\.files) }

    /// "3/14" while several videos are queued; nil for a lone video.
    var queueLabel: String? {
        let s = summary
        guard s.units > 1, let position = s.currentPosition else { return nil }
        return "\(position)/\(s.units)"
    }

    // MARK: Adding links
    /// Accepts one link or several separated by spaces or new lines. Returns how many were queued.
    @discardableResult
    func add(_ text: String) -> Int {
        let links = Self.links(in: text)
        guard !links.isEmpty else {
            status = "Paste a link to a video or playlist."
            return 0
        }
        idleTask?.cancel()

        // a fresh session: drop what finished last time
        if !isActive {
            jobs.removeAll { $0.isFinished }
            hadError = false
            stopQueue = false
        }

        var added = 0
        let options = JobOptions.current()
        for link in links {
            if jobs.contains(where: { $0.url == link && !$0.isFinished }) { continue }
            let job = DownloadJob(url: link, options: options)
            jobs.append(job)
            toResolve.append(job.id)
            added += 1
        }
        if added == 0 {
            status = "Already in the queue."
        } else if isDownloading {
            status = added == 1 ? "Added to the queue." : "Added \(added) to the queue."
        } else {
            status = "Checking link…"
        }
        resolveNext()
        return added
    }

    nonisolated static func links(in text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace })
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "<>\"',")) }
            .filter { raw in
                if raw.lowercased().hasPrefix("ytsearch") { return true }
                guard let url = URL(string: raw), let scheme = url.scheme?.lowercased() else { return false }
                return (scheme == "http" || scheme == "https") && url.host != nil
            }
    }

    // MARK: Controlling
    /// Stop the download in progress; the queue carries on with the next one.
    func cancelCurrent() {
        guard process != nil else { return }
        wasCancelled = true
        process?.terminate()
    }

    /// Stop everything, including what is waiting.
    func cancelAll() {
        stopQueue = true
        for i in jobs.indices where jobs[i].state == .queued { jobs[i].state = .cancelled }
        if process != nil {
            wasCancelled = true
            process?.terminate()
        } else {
            status = "Download cancelled."
        }
    }

    /// Move a waiting link to another place in the queue. Links that are running or finished stay put,
    /// and a waiting link never goes above them.
    func move(_ id: UUID, toIndex: Int) {
        let waiting = jobs.map { $0.state == .queued }
        guard let from = jobs.firstIndex(where: { $0.id == id }),
            let to = QueueOrder.destination(from: from, to: toIndex, waiting: waiting)
        else { return }
        jobs.insert(jobs.remove(at: from), at: to)
    }

    /// Remove a waiting or finished job, or stop a running one.
    func remove(_ id: UUID) {
        if id == runningID {
            cancelCurrent()
        } else {
            jobs.removeAll { $0.id == id }
            if jobs.isEmpty { status = "Idle" }
        }
    }

    func retry(_ id: UUID) {
        guard let i = jobs.firstIndex(where: { $0.id == id }), jobs[i].isFinished, jobs[i].state != .done
        else { return }
        if let failed = jobs[i].playlist?.failed.map(\.id), !failed.isEmpty {
            jobs[i].only = failed
        } else {
            jobs[i].only = nil
            jobs[i].fraction = 0
            if var p = jobs[i].playlist {
                for k in p.items.indices where p.items[k].state != .done {
                    p.items[k].state = .queued
                    p.items[k].fraction = 0
                }
                jobs[i].playlist = p
            }
        }
        jobs[i].state = .queued
        jobs[i].detail = nil
        stopQueue = false
        hadError = jobs.contains { $0.state == .failed }
        pump()
    }

    func retryAllFailed() {
        for job in jobs where job.state == .failed || job.state == .cancelled { retry(job.id) }
    }

    /// Drop everything that has finished.
    func clearFinished() {
        jobs.removeAll { $0.isFinished }
        if jobs.isEmpty {
            hadError = false
            status = "Idle"
        }
    }

    /// Show one job's files in Finder.
    func reveal(job id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        if job.files.isEmpty {
            NSWorkspace.shared.open(job.options.folder)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(job.files)
        }
    }

    func revealFiles() {
        let files = lastFiles
        if files.isEmpty {
            NSWorkspace.shared.open(JobOptions.current().folder)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(files)
        }
    }

    // MARK: Looking links up
    private func resolveNext() {
        guard !resolving else { return }
        while let id = toResolve.first {
            toResolve.removeFirst()
            guard let job = jobs.first(where: { $0.id == id }), job.isResolving else { continue }
            resolving = true
            let path = Self.path(for: .ytDlp)
            let url = job.url
            let only = job.only
            Task.detached { [weak self] in
                let result = Self.probe(url: url, ytDlp: path, only: only)
                await self?.applyProbe(result, to: id)
            }
            return
        }
        pump()
    }

    private func applyProbe(_ result: ProbeResult?, to id: UUID) {
        resolving = false
        if let i = jobs.firstIndex(where: { $0.id == id }) {
            jobs[i].isResolving = false
            if let result {
                jobs[i].title = result.playlistTitle ?? result.titles.first
                if let name = result.playlistTitle, result.titles.count > 1, jobs[i].state == .queued {
                    jobs[i].playlist = PlaylistProgress(
                        title: name,
                        items: result.titles.enumerated().map {
                            PlaylistItem(id: $0.offset + 1, title: $0.element)
                        },
                        current: nil, speed: nil)
                }
            }
        }
        resolveNext()
    }

    struct ProbeResult {
        var playlistTitle: String?
        var titles: [String]
    }

    /// One quick yt-dlp call that lists titles without downloading anything.
    nonisolated private static func probe(url: String, ytDlp: String, only: [Int]?) -> ProbeResult? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ytDlp)
        var args = ["--flat-playlist", "--no-warnings", "--print", "%(playlist_title|)s\t%(title)s"]
        if let only { args += ["--playlist-items", only.map(String.init).joined(separator: ",")] }
        args.append(url)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return nil }

        // a link that never answers must not hold up the queue
        let watchdog = DispatchWorkItem { if proc.isRunning { proc.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 45, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        watchdog.cancel()
        guard proc.terminationStatus == 0 else { return nil }

        let lines = (String(data: data, encoding: .utf8) ?? "")
            .split(whereSeparator: \.isNewline).map(String.init)
        guard !lines.isEmpty else { return nil }
        var playlistTitle: String?
        var titles: [String] = []
        for line in lines {
            let parts = line.components(separatedBy: "\t")
            if parts.count >= 2 {
                if playlistTitle == nil, !parts[0].isEmpty, parts[0] != "NA" { playlistTitle = parts[0] }
                titles.append(parts[1])
            } else {
                titles.append(line)
            }
        }
        return ProbeResult(playlistTitle: playlistTitle, titles: titles)
    }

    // MARK: Running
    private func pump() {
        guard runningID == nil, !stopQueue else { return }
        guard let next = jobs.first(where: { $0.state == .queued }) else {
            finishQueue()
            return
        }
        // wait for the look-up so the job starts with real titles
        if next.isResolving {
            status = "Checking link…"
            resolveNext()
            return
        }
        run(next.id)
    }

    private func run(_ id: UUID) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        let job = jobs[i]
        let fm = FileManager.default
        let ytDlpPath = Self.path(for: .ytDlp)
        let ffmpegPath = Self.path(for: .ffmpeg)
        let ffprobePath = Self.path(for: .ffprobe)

        func stop(_ message: String) {
            jobs[i].state = .failed
            jobs[i].detail = message
            hadError = true
            status = message
            pump()  // a missing folder should not block the links that can still run
        }
        guard fm.fileExists(atPath: job.options.folder.path) else {
            stop("Destination folder not found.")
            return
        }
        guard fm.isExecutableFile(atPath: ytDlpPath) else {
            stop("yt‑dlp not found.\nInstall it in Settings → Requirements.")
            return
        }
        guard fm.isExecutableFile(atPath: ffmpegPath), fm.isExecutableFile(atPath: ffprobePath) else {
            stop("ffmpeg / ffprobe not found.\nInstall them in Settings → Requirements.")
            return
        }

        var args = Self.formatArguments(for: job.options)
        let pathFile = fm.temporaryDirectory.appendingPathComponent("downer-\(UUID().uuidString).txt")
        self.pathFile = pathFile
        args += ["--print-to-file", "after_move:filepath", pathFile.path]
        args += ["--newline", "--ffmpeg-location", (ffmpegPath as NSString).deletingLastPathComponent]
        if let only = job.only { args += ["--playlist-items", only.map(String.init).joined(separator: ",")] }
        args.append(job.url)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ytDlpPath)
        proc.arguments = args
        proc.currentDirectoryURL = job.options.folder
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
                for line in complete { self?.handle(line: line, job: id) }
            }
        }
        proc.terminationHandler = { [weak self] p in
            pipe.fileHandleForReading.readabilityHandler = nil
            let code = p.terminationStatus
            Task { @MainActor in self?.finished(code: code, job: id) }
        }

        tracker = job.playlist == nil && job.only == nil
            ? PlaylistTracker()
            : PlaylistTracker(retrying: job.only, keeping: job.playlist)
        wasCancelled = false
        lastErrorLine = nil
        jobs[i].state = .running
        jobs[i].detail = nil
        runningID = id
        process = proc
        status = "Starting download…"

        do {
            try proc.run()
        } catch {
            process = nil
            runningID = nil
            stop("Could not start yt‑dlp: \(error.localizedDescription)")
        }
    }

    nonisolated static func path(for tool: Tool) -> String {
        UserDefaults.standard.string(forKey: tool.defaultsKey) ?? tool.defaultPath
    }

    // MARK: Arguments
    nonisolated static func formatArguments(for o: JobOptions) -> [String] {
        func abr(_ quality: String) -> Int? { Int(quality.replacingOccurrences(of: "k", with: "")) }
        let audioFilter = abr(o.audioQuality).map { "bestaudio[abr<=\($0)][vcodec=none]" } ?? "bestaudio"

        switch o.type {
        case .audio:
            var args = ["-f", audioFilter]
            if o.audioFormat != "source" {  // transcode only if asked
                args += ["--extract-audio", "--audio-format", o.audioFormat]
                if let rate = abr(o.audioQuality), rate <= 160 {
                    args += ["--audio-quality", o.audioQuality]
                }
            }
            return args
        case .video:
            return ["-f", "bestvideo[height<=\(o.resolution)][acodec=none]", "--remux-video", o.container]
        case .both:
            return [
                "-f", "bestvideo[height<=\(o.resolution)]+\(audioFilter)",
                "--merge-output-format", o.container,
            ]
        }
    }

    // MARK: Output
    private func handle(line raw: String, job id: UUID) {
        guard id == runningID, let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("ERROR") { lastErrorLine = line }

        tracker.consume(line)
        if tracker.progress != jobs[i].playlist { jobs[i].playlist = tracker.progress }
        if let p = jobs[i].playlist {
            jobs[i].speed = p.speed
        } else {
            jobs[i].fraction = max(jobs[i].fraction, tracker.fileFraction)
            jobs[i].speed = tracker.fileSpeed
            if jobs[i].title == nil { jobs[i].title = tracker.fileTitle }
        }

        // "[download]  42.3% of  120.00MiB at  3.20MiB/s ETA 00:24"
        if line.hasPrefix("[download]"), let pct = Self.percent(in: line) {
            let prefix = queuePrefix()
            if let p = jobs[i].playlist {
                let current = p.current.map { "Item \($0) of \(p.total)" } ?? "Playlist"
                var text = prefix + "\(current) · \(Int(pct.rounded()))%"
                if let speed = p.speed { text += " · \(speed)" }
                status = text
            } else {
                var text = prefix + "Downloading \(Int((jobs[i].fraction * 100).rounded()))%"
                if let speed = Self.value(after: " at ", in: line) { text += " · \(speed)" }
                if let eta = Self.value(after: "ETA ", in: line) { text += " · \(eta) left" }
                status = text
            }
            return
        }
        // Only yt-dlp's own tagged lines are worth showing; ffmpeg chatter is not.
        guard line.hasPrefix("[") || line.hasPrefix("Deleting original file") else { return }
        if line.hasPrefix("[Merger]") || line.hasPrefix("[VideoRemuxer]") {
            status = queuePrefix() + "Merging…"
        } else if line.hasPrefix("[ExtractAudio]") {
            status = queuePrefix() + "Converting audio…"
        } else if line.hasPrefix("[download] Downloading item"), let p = jobs[i].playlist, let current = p.current {
            status = queuePrefix() + "Item \(current) of \(p.total)"
        } else if line.hasPrefix("[download]") || line.contains("%(filepath)s") {
            return
        } else if line.hasPrefix("Deleting original file") {
            status = queuePrefix() + "Finishing…"
        } else if jobs[i].playlist == nil {
            status = queuePrefix() + line
        }
    }

    /// "Link 2 of 5 · " when several links are queued.
    private func queuePrefix() -> String {
        guard jobs.count > 1, let running = jobs.firstIndex(where: { $0.id == runningID }) else { return "" }
        return "Link \(running + 1) of \(jobs.count) · "
    }

    private func finished(code: Int32, job id: UUID) {
        guard id == runningID else { return }
        process = nil
        runningID = nil
        tracker.finish(exitCode: code, cancelled: wasCancelled)

        let files = pathFile
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }?
            .split(whereSeparator: \.isNewline).map { URL(fileURLWithPath: String($0)) } ?? []
        if let pathFile { try? FileManager.default.removeItem(at: pathFile) }
        pathFile = nil

        guard let i = jobs.firstIndex(where: { $0.id == id }) else {
            pump()
            return
        }
        if tracker.progress != nil { jobs[i].playlist = tracker.progress }
        jobs[i].files += files
        jobs[i].speed = nil

        if wasCancelled {
            jobs[i].state = .cancelled
        } else if let playlist = jobs[i].playlist, !jobs[i].autoRetried,
            !playlist.failed.isEmpty, playlist.failed.allSatisfy({ DownloadJob.isTransient($0.detail) })
        {
            // a network hiccup: try just the failed videos once more
            jobs[i].autoRetried = true
            jobs[i].only = playlist.failed.map(\.id)
            jobs[i].state = .queued
            status = "Retrying \(playlist.failed.count) that hit a network error…"
        } else if jobs[i].playlist == nil, code != 0, !jobs[i].autoRetried,
            DownloadJob.isTransient(lastErrorLine.map { PlaylistTracker.reason(from: $0) })
        {
            jobs[i].autoRetried = true
            jobs[i].state = .queued
            status = "Retrying after a network error…"
        } else if let playlist = jobs[i].playlist {
            if playlist.failed.isEmpty && code == 0 {
                jobs[i].state = .done
                completions += 1
            } else {
                jobs[i].state = .failed
                jobs[i].detail = "\(playlist.doneCount) of \(playlist.total) downloaded"
                hadError = true
            }
        } else if code == 0 {
            jobs[i].state = .done
            jobs[i].fraction = 1
            completions += 1
        } else {
            jobs[i].state = .failed
            jobs[i].detail = lastErrorLine.map { PlaylistTracker.reason(from: $0) } ?? "Failed (code \(code))"
            hadError = true
        }
        let stopped = stopQueue && wasCancelled
        wasCancelled = false
        if stopped {
            // Cancel All: pump() will not run, so say so here
            status = "Download cancelled."
            scheduleIdle()
        }
        pump()
    }

    /// Nothing left to run: describe how it went.
    private func finishQueue() {
        guard !jobs.isEmpty else { return }
        let s = summary
        if jobs.allSatisfy({ $0.state == .cancelled }) {
            status = "Download cancelled."
        } else if jobs.contains(where: { $0.state == .failed }) {
            if jobs.count == 1, !jobs[0].isPlaylist {
                status = "Download failed.\n" + (jobs[0].detail ?? "")
            } else {
                let failed = max(s.failedUnits, jobs.filter { $0.state == .failed }.count)
                status = "\(s.doneUnits) of \(s.units) downloaded · \(failed) failed"
            }
            return  // keep the summary on screen until the next attempt
        } else if jobs.count == 1 {
            status = jobs[0].isPlaylist ? "Playlist completed." : "Download completed."
        } else {
            status = "All \(s.units) downloads completed."
        }
        scheduleIdle()
    }

    /// Return to "Idle" a little while after a clean finish.
    private func scheduleIdle() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.resetIfIdle()
        }
    }

    private func resetIfIdle() {
        if !isActive { status = "Idle" }
    }

    // MARK: Parsing helpers
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
