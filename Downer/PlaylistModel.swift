//
//  PlaylistModel.swift
//  Downer
//
//  Follows a yt-dlp playlist run line by line: which item is downloading, how
//  far along it is, and which items finished or failed. Pure Foundation, so it
//  can be tested against recorded yt-dlp output.
//

import Foundation

struct PlaylistItem: Identifiable, Equatable {
    enum State: Equatable { case queued, running, done, failed }

    /// 1-based position in the playlist.
    let id: Int
    var title: String?
    var state: State = .queued
    var fraction: Double = 0
    var detail: String?
}

struct PlaylistProgress: Equatable {
    var title: String
    var items: [PlaylistItem]
    /// Position (1-based) of the item being downloaded, if any.
    var current: Int?
    var speed: String?

    var total: Int { items.count }
    var doneCount: Int { items.filter { $0.state == .done }.count }
    var failed: [PlaylistItem] { items.filter { $0.state == .failed } }

    /// 0...1 across the whole playlist.
    var overall: Double {
        guard total > 0 else { return 0 }
        let running = items.first { $0.state == .running }?.fraction ?? 0
        return min(1, (Double(doneCount) + running) / Double(total))
    }
}

struct PlaylistTracker {
    private(set) var progress: PlaylistProgress?

    private var playlistName = ""
    /// yt-dlp numbers a filtered retry run 1…n; this maps that back to the real positions.
    private var indexMap: [Int]?
    private var passes = 1
    private var passIndex = 0
    /// Progress of the current video across its streams (video then audio), for
    /// single videos as well as playlist items.
    private(set) var fileFraction: Double = 0
    private(set) var fileSpeed: String?
    private(set) var fileTitle: String?

    init(retrying map: [Int]? = nil, keeping previous: PlaylistProgress? = nil) {
        indexMap = map
        progress = previous
        if let previous { playlistName = previous.title }
    }

    // MARK: Lines
    mutating func consume(_ raw: String) {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if let name = line.value(after: "[download] Downloading playlist: ") {
            playlistName = name
        } else if let (n, m) = Self.itemLine(line) {
            startItem(n, of: m)
        } else if line.hasPrefix("[info]"), line.contains("format(s):") {
            // "[info] ID: Downloading 1 format(s): 395+251"
            let formats = line.components(separatedBy: "format(s):").last ?? ""
            passes = max(1, formats.split(separator: "+").count)
        } else if let name = line.value(after: "[download] Destination: ") {
            passIndex += 1
            if fileTitle == nil { fileTitle = Self.title(fromFile: name) }
            if var p = progress, let current = p.current, p.items[index(current)].title == nil {
                p.items[index(current)].title = Self.title(fromFile: name)
                progress = p
            }
        } else if line.hasPrefix("[download]"), let pct = Self.percent(line) {
            let done = Double(max(0, passIndex - 1))
            let value = passIndex <= passes ? (done + pct / 100) / Double(passes) : pct / 100
            fileFraction = min(1, max(fileFraction, value))
            fileSpeed = line.value(after: " at ")?.firstWord ?? fileSpeed
            updateProgress(pct / 100, speed: fileSpeed)
        } else if line.hasPrefix("ERROR:") {
            failCurrent(Self.reason(from: line))
        }
    }

    /// Fill in the real titles once they are known (fetched separately, in order).
    mutating func setTitles(_ titles: [String]) {
        guard var p = progress else { return }
        for (offset, title) in titles.enumerated() {
            let position: Int
            if let map = indexMap {
                guard offset < map.count else { continue }
                position = map[offset]
            } else {
                position = offset + 1
            }
            guard position >= 1, position <= p.items.count else { continue }
            p.items[position - 1].title = title
        }
        progress = p
    }

    /// Call when the process has ended.
    mutating func finish(exitCode: Int32, cancelled: Bool) {
        guard var p = progress else { return }
        for i in p.items.indices where p.items[i].state == .running {
            if cancelled {
                p.items[i].state = .queued
                p.items[i].fraction = 0
            } else if exitCode == 0 || p.items[i].fraction >= 0.99 {
                // yt-dlp exits non-zero when any earlier item failed; this one still finished
                p.items[i].state = .done
                p.items[i].fraction = 1
            } else {
                p.items[i].state = .failed
                p.items[i].detail = "Stopped before it finished"
            }
        }
        p.current = nil
        p.speed = nil
        progress = p
    }

    // MARK: Items
    private func index(_ position: Int) -> Int { position - 1 }

    private mutating func startItem(_ n: Int, of m: Int) {
        let total = indexMap == nil ? m : (progress?.total ?? m)
        if progress == nil || progress?.total != total {
            guard total > 1 else { return }  // a single video is not a playlist
            progress = PlaylistProgress(
                title: playlistName,
                items: (1...total).map { PlaylistItem(id: $0) }
            )
        }
        guard var p = progress else { return }
        p.title = playlistName.isEmpty ? p.title : playlistName

        // the previous item finished cleanly if it was still running
        if let previous = p.current, p.items[index(previous)].state == .running {
            p.items[index(previous)].state = .done
            p.items[index(previous)].fraction = 1
        }
        let position = indexMap.map { n - 1 < $0.count ? $0[n - 1] : n } ?? n
        guard position >= 1, position <= p.items.count else { return }
        p.items[index(position)].state = .running
        p.items[index(position)].fraction = 0
        p.items[index(position)].detail = nil
        p.current = position
        progress = p
        passIndex = 0
        passes = 1
        fileFraction = 0
        fileTitle = nil
    }

    private mutating func updateProgress(_ pct: Double, speed: String?) {
        guard var p = progress, let current = p.current else { return }
        let done = Double(max(0, passIndex - 1))
        let fraction = passIndex <= passes ? (done + pct) / Double(passes) : pct
        p.items[index(current)].fraction = min(1, max(p.items[index(current)].fraction, fraction))
        p.speed = speed
        progress = p
    }

    private mutating func failCurrent(_ reason: String) {
        guard var p = progress, let current = p.current else { return }
        p.items[index(current)].state = .failed
        p.items[index(current)].detail = reason
        progress = p
    }

    // MARK: Parsing helpers
    static func itemLine(_ line: String) -> (Int, Int)? {
        // "[download] Downloading item 3 of 12"
        guard let rest = line.value(after: "[download] Downloading item ") else { return nil }
        let parts = rest.split(separator: " ")
        guard parts.count >= 3, parts[1] == "of", let n = Int(parts[0]), let m = Int(parts[2]) else {
            return nil
        }
        return (n, m)
    }

    static func percent(_ line: String) -> Double? {
        guard let r = line.range(of: #"(\d+(?:\.\d+)?)%"#, options: .regularExpression) else {
            return nil
        }
        return Double(line[r].dropLast())
    }

    /// "Me at the zoo [jNQXAC9IVRw].f251.webm" → "Me at the zoo"
    static func title(fromFile name: String) -> String {
        var base = (name as NSString).lastPathComponent
        base = (base as NSString).deletingPathExtension
        if base.range(of: #"\.f\d+$"#, options: .regularExpression) != nil {
            base = (base as NSString).deletingPathExtension
        }
        if let r = base.range(of: #" \[[\w-]{6,}\]$"#, options: .regularExpression) {
            base.removeSubrange(r)
        }
        return base
    }

    /// "ERROR: [youtube] abc123: Video unavailable" → "Video unavailable"
    static func reason(from line: String) -> String {
        var text = String(line.dropFirst("ERROR:".count)).trimmingCharacters(in: .whitespaces)
        while text.hasPrefix("[") {
            guard let close = text.firstIndex(of: "]") else { break }
            text = String(text[text.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }
        if let colon = text.range(of: ": "), text[..<colon.lowerBound].count <= 16 {
            text = String(text[colon.upperBound...])  // drop "abc123: "
        }
        return String(text.prefix(80))
    }
}

extension String {
    func value(after marker: String) -> String? {
        guard hasPrefix(marker) || contains(marker),
            let r = range(of: marker)
        else { return nil }
        let rest = self[r.upperBound...].trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : rest
    }

    var firstWord: String? { split(separator: " ").first.map(String.init) }
}
