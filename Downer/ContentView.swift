//
//  ContentView.swift
//  Downer
//
//  Created by Dumindu Sameendra on 2025-04-17.
//

import SwiftUI

struct ContentView: View {
    @State private var videoURL: String = ""
    @State private var downloadStatus: String = "Idle"
    
    var body: some View {
        VStack(spacing: 20) {
            Text("YouTube Video Downloader")
                .font(.title)
                .padding(.top)
            
            TextField("Enter YouTube video URL", text: $videoURL)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            
            Button("Download") {
                downloadYouTubeVideo(url: videoURL)
            }
            .disabled(videoURL.isEmpty)
            
            Text(downloadStatus)
                .foregroundColor(.gray)
                .padding()
            
            Spacer()
        }
        .frame(width: 500, height: 300)
        .padding()
    }
    
    func downloadYouTubeVideo(url: String) {
        downloadStatus = "Starting download..."
        print("Starting download for URL: \(url)")
        
        let desktopPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        if !FileManager.default.fileExists(atPath: desktopPath.path) {
            downloadStatus = "Desktop folder not found."
            print("Error: Desktop path not found.")
            return
        }
        
        let safeURL = url.escaped()
        let safeOutputPath = desktopPath.path.escaped()
        
        let ytDlpPath = "/opt/homebrew/bin/yt-dlp"
        let fullCommand = "cd \(safeOutputPath) && \(ytDlpPath) \"\(safeURL)\""
        print("Running shell command: \(fullCommand)")
        
        let process = Process()
        process.launchPath = "/bin/zsh"
        process.arguments = ["-c", fullCommand]
        
        let ioPipe = Pipe()
        process.standardOutput = ioPipe
        process.standardError = ioPipe
        
        ioPipe.fileHandleForReading.readabilityHandler = { handle in
            if let output = String(data: handle.availableData, encoding: .utf8), !output.isEmpty {
                DispatchQueue.main.async {
                    self.downloadStatus = output
                }
                print("📥 [yt-dlp output] \(output)")
            }
        }
        
        process.terminationHandler = { process in
            DispatchQueue.main.async {
                if process.terminationStatus == 0 {
                    self.downloadStatus = "Download completed. Check Desktop."
                    print("Process finished successfully.")
                } else {
                    self.downloadStatus = "Download failed. See logs."
                    print("Process exited with code \(process.terminationStatus).")
                }
            }
        }
        
        do {
            try process.run()
            print("Process launched.")
        } catch {
            downloadStatus = "Failed to start yt-dlp."
            print("Error launching process: \(error.localizedDescription)")
        }
    }
}
#Preview {
    ContentView()
}

extension String {
    func escaped() -> String {
        self.replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: " ", with: "\\ ")
    }
}
