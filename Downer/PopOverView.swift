//
//  PopOverView.swift
//  Downer
//
//  Created by Dumindu Sameendra on 2025-04-17.
//

import AppKit
import SwiftUI

struct PopOverView: View {
    @ObservedObject private var dl = DownloadManager.shared
    @State private var videoURL = ""
    @FocusState private var urlFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var addsToQueue: Bool { !videoURL.isEmpty && dl.isActive }
    private var cancels: Bool { videoURL.isEmpty && dl.isActive }

    private func submit() {
        guard !videoURL.isEmpty else { return }
        if dl.add(videoURL) > 0 {
            withAnimation(Motion.standard(reduce: reduceMotion)) { videoURL = "" }
        }
    }

    // MARK: - Body
    // NSPopover supplies the system glass behind this view, so no ground is drawn here.
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "link")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Enter video/playlist URL", text: $videoURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($urlFocused)
                    .onSubmit(submit)

                if videoURL.isEmpty {
                    Button("Paste") {
                        if let s = NSPasteboard.general.string(forType: .string) {
                            videoURL = s.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    .buttonStyle(PillButtonStyle())
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .padding(.leading, 15)
            .padding(.trailing, 8)
            .frame(height: 44)
            .background(Color.primary.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(Brand.red.opacity(urlFocused ? 0.55 : 0), lineWidth: 1.5))
            .motion(Motion.quick, value: urlFocused)
            .motion(Motion.quick, value: videoURL.isEmpty)

            Button {
                if cancels { dl.cancelAll() } else { submit() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: cancels ? "xmark" : (addsToQueue ? "plus" : "arrow.down"))
                        .font(.system(size: 14, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                    Text(cancels ? "Cancel" : (addsToQueue ? "Add to Queue" : "Download"))
                        .contentTransition(.opacity)
                }
                .motion(Motion.quick, value: cancels)
                .motion(Motion.quick, value: addsToQueue)
            }
            .buttonStyle(DownloadButtonStyle(isCancel: cancels, height: 46, flat: true))
            .keyboardShortcut(cancels ? nil : .defaultAction)
            .disabled(videoURL.isEmpty && !dl.isActive)

            DownloadStatusLine(
                status: dl.status,
                isDownloading: dl.isActive,
                completions: dl.completions
            )
            .frame(maxHeight: .infinity)
        }
        // Opened by the menu bar icon or the global shortcut: pick up a copied
        // link and put the cursor in the field, so copy → shortcut → Return works.
        .onReceive(NotificationCenter.default.publisher(for: .popoverWillShow)) { _ in
            if videoURL.isEmpty, let copied = Self.copiedLink() {
                withAnimation(Motion.standard(reduce: reduceMotion)) { videoURL = copied }
            }
            urlFocused = true
        }
        .padding(16)
        .frame(width: 360, height: 180)
        .tint(Brand.red)
    }

    private static func copiedLink() -> String? {
        guard
            let text = NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.contains("\n"),
            let url = URL(string: text),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            url.host != nil
        else { return nil }
        return text
    }
}

extension Notification.Name {
    static let popoverWillShow = Notification.Name("DownerPopoverWillShow")
}
