//
//  DownloadJob.swift
//  Downer
//
//  One entry in the download queue: a link to a single video or to a whole
//  playlist, with the settings it was added with.
//

import Foundation

/// The settings a job runs with, captured when it is added, so changing the
/// selectors later never alters what is already queued.
struct JobOptions: Equatable {
    var type: DownloadType
    var resolution: String
    var container: String
    var audioQuality: String
    var audioFormat: String
    var folder: URL

    static func current(_ defaults: UserDefaults = .standard) -> JobOptions {
        let downloads =
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
            ?? NSHomeDirectory()
        return JobOptions(
            type: DownloadType(rawValue: defaults.string(forKey: "downloadType") ?? "") ?? .both,
            resolution: defaults.string(forKey: "selectedResolution") ?? "1080",
            container: defaults.string(forKey: "selectedVideoFormat") ?? "mp4",
            audioQuality: defaults.string(forKey: "selectedAudioQuality") ?? "source",
            audioFormat: defaults.string(forKey: "selectedAudioFormat") ?? "opus",
            folder: URL(fileURLWithPath: defaults.string(forKey: "destinationFolder") ?? downloads)
        )
    }
}

struct DownloadJob: Identifiable, Equatable {
    enum State: Equatable { case queued, running, done, failed, cancelled }

    let id = UUID()
    let url: String
    let options: JobOptions
    var state: State = .queued
    /// A video's title, or a playlist's name.
    var title: String?
    /// 0…1 for a single video.
    var fraction: Double = 0
    var speed: String?
    /// Why it failed, in one line.
    var detail: String?
    /// Set when the link is a playlist.
    var playlist: PlaylistProgress?
    /// True until the link has been looked up; a job waits for this before it starts.
    var isResolving = true
    var files: [URL] = []
    /// When retrying, the playlist positions to fetch again.
    var only: [Int]?
    /// Set once a network hiccup has been retried automatically.
    var autoRetried = false

    var isPlaylist: Bool { playlist != nil }
    var isFinished: Bool { state == .done || state == .failed || state == .cancelled }

    /// How many downloads this job stands for (a playlist counts every video).
    var units: Int { max(1, playlist?.total ?? 1) }

    var doneUnits: Int {
        if let playlist { return playlist.doneCount }
        return state == .done ? 1 : 0
    }

    var failedUnits: Int {
        if let playlist { return playlist.failed.count }
        return state == .failed ? 1 : 0
    }

    /// 0…1 across this job.
    var progress: Double {
        if let playlist { return state == .done ? 1 : playlist.overall }
        return state == .done ? 1 : fraction
    }

    var displayTitle: String {
        title ?? (isResolving ? "Checking link…" : Self.shortName(of: url))
    }

    static func shortName(of url: String) -> String {
        guard let parsed = URL(string: url), let host = parsed.host else { return url }
        let trimmed = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        var name = trimmed + parsed.path
        if let query = parsed.query, !query.isEmpty { name += "?" + query }
        return name
    }

    /// Network-level failures are worth one more try; "unavailable" or "private" are not.
    static func isTransient(_ reason: String?) -> Bool {
        guard let reason = reason?.lowercased() else { return false }
        let permanent = ["unavailable", "private", "copyright", "sign in", "age", "members", "removed", "not available", "geo"]
        if permanent.contains(where: reason.contains) { return false }
        let transient = ["http error 4", "http error 5", "timed out", "connection", "reset by peer", "temporary failure", "unable to download", "incomplete", "stopped before"]
        return transient.contains(where: reason.contains)
    }
}

/// Queue-wide numbers, derived from the jobs.
struct QueueSummary: Equatable {
    var jobs: [DownloadJob]

    var units: Int { jobs.reduce(0) { $0 + $1.units } }
    var doneUnits: Int { jobs.reduce(0) { $0 + $1.doneUnits } }
    var failedUnits: Int { jobs.reduce(0) { $0 + $1.failedUnits } }
    var isActive: Bool { jobs.contains { $0.state == .running || $0.state == .queued } }

    /// 0…1 across everything in the queue; finished-but-failed videos count as handled.
    var overall: Double {
        let total = Double(units)
        guard total > 0 else { return 0 }
        let handled = jobs.reduce(0.0) { sum, job in
            switch job.state {
            case .done: return sum + Double(job.units)
            case .queued: return sum
            case .running, .failed, .cancelled:
                if let playlist = job.playlist {
                    return sum + Double(playlist.doneCount + playlist.failed.count)
                        + (job.state == .running ? (playlist.items.first { $0.state == .running }?.fraction ?? 0) : 0)
                }
                return sum + (job.state == .running ? job.fraction : (job.state == .failed ? 1 : 0))
            }
        }
        return min(1, handled / total)
    }

    /// Position of the video being downloaded among all videos, 1-based.
    var currentPosition: Int? {
        guard let running = jobs.first(where: { $0.state == .running }) else { return nil }
        var before = 0
        for job in jobs {
            if job.id == running.id { break }
            before += job.units
        }
        if let current = running.playlist?.current { return before + current }
        return before + 1
    }
}
