//
//  AppModel.swift
//  YoutubeDL
//
//  Based on original by Changbeom Ahn
//

import Foundation
@preconcurrency import PythonSupport
@preconcurrency import PythonKit
@preconcurrency import YoutubeDL
import Combine
import UIKit
import AVFoundation
import Photos

// For Python.None etc
let Python = PythonKit.Python

@MainActor
class AppModel: ObservableObject {
    // MARK: - Published state
    
    @Published var url: URL?
    
    @Published var youtubeDL = YoutubeDL()
    
    @Published var enableChunkedDownload = true
    @Published var enableTranscoding = true
    @Published var supportedFormatsOnly = true
    @Published var exportToPhotos = true
    
    @Published var fileURL: URL?
    @Published var downloads: [URL] = []
    
    @Published var showProgress = false
    var progress = Progress()
    
    @Published var error: Error?
    
    // When Instagram falls back to WebView
    @Published var webViewURL: URL?
    
    // Full raw text from the last `yt-dlp -F` run (kept for debugging if needed)
    @Published var lastFormatOutput: String = ""
    
    // MARK: - Format listing from yt-dlp
    
    struct FormatChoice: Identifiable, Hashable {
        let id: String            // format_id (e.g. "140", "96", "sb0")
        let description: String   // entire line from the table (what user sees)
        let isAudioOnly: Bool
        let isVideoOnly: Bool
        let isMuxed: Bool
    }
    
    @Published var formatChoices: [FormatChoice] = []
    @Published var selectedFormatID: String?
    
    lazy var subscriptions = Set<AnyCancellable>()
    
    // MARK: - Init
    
    init() {
        youtubeDL.downloadsDirectory = try! documentsDirectory()
        
        do {
            downloads = try loadDownloads()
        } catch {
            print(#function, error)
        }
    }
    
    // MARK: - Fetch formats using `yt-dlp -F`
    
    /// Runs `yt-dlp -F <url>` and parses every table row into a FormatChoice
    func fetchFormats(for url: URL) async {
        print(#function, url)
        
        showProgress = true
        progress.localizedDescription = "Getting formats..."
        formatChoices = []
        selectedFormatID = nil
        lastFormatOutput = ""
        
        var logLines: [String] = []
        var errorMessage: String?
        
        do {
            let argv = [
                "-F",
                "--no-check-certificates",
                url.absoluteString
            ]
            print(#function, "argv:", argv)

            try await yt_dlp(argv: argv) { dict in
                // For -F we don't really care about hook dicts; just log for debugging
                print(#function, "hook dict:", dict)
            } log: { level, message in
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                print(#function, "yt-dlp [\(level)] \(trimmed)")

                let cleaned = trimmed
                    .removingANSIEscapeSequences()
                    .removingControlCharacters()
                    .trimmingCharacters(in: .whitespaces)

                if !cleaned.isEmpty {
                    logLines.append(cleaned)
                }

                if level == "error" {
                    errorMessage = cleaned.isEmpty ? trimmed : cleaned
                }
            } makeTranscodeProgressBlock: {
                // No transcoding when just listing formats; return a no-op closure
                return { _ in }
            }
        } catch {
            print(#function, "yt-dlp error:", error)
            self.error = error
            showProgress = false
            progress.localizedDescription = nil
            return
        }
        
        if let errorMessage {
            self.error = NSError(
                domain: "yt-dlp",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: errorMessage]
            )
        }
        
        let fullOutput = logLines.joined(separator: "\n")
        self.lastFormatOutput = fullOutput
        
        let choices = parseFormatChoices(from: fullOutput)
        
        self.formatChoices = choices
        self.selectedFormatID = choices.first?.id
        
        print(#function, "parsed \(choices.count) format choices")
        
        showProgress = false
        progress.localizedDescription = nil
    }
    
    /// SUPER TOLERANT parser:
    /// - scans EVERY line of the log text
    /// - ignores noise ([youtube], [info], warnings, etc.)
    /// - skips header row "ID  EXT ..." and the dashed separator
    /// - treats remaining “table-looking” lines as formats
    /// - first token becomes format_id, full line becomes description
    private func parseFormatChoices(from output: String) -> [FormatChoice] {
        var results: [FormatChoice] = []
        
        let lines = output.components(separatedBy: .newlines)

        for raw in lines {
            let line = raw
                .removingANSIEscapeSequences()
                .removingControlCharacters()
                .trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            // Skip obvious non-table noise
            if line.hasPrefix("[") { continue }                         // [youtube]..., [info]...
            if line.lowercased().contains("available formats for") {    // header text
                continue
            }
            if line.hasPrefix("ID ") { continue }                       // header row
            if line.allSatisfy({ $0 == "-" }) { continue }              // separator row
            
            // Tokenize
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard let first = parts.first, !first.isEmpty else { continue }
            
            // Rough filter: first token must start with letter or digit (e.g. 140, 137, sb0, 139-drc)
            guard let c = first.first, c.isLetter || c.isNumber else { continue }
            
            let formatID = first
            
            let lower = line.lowercased()
            let isAudioOnly = lower.contains("audio only") && !lower.contains("video only")
            let isVideoOnly = lower.contains("video only") && !lower.contains("audio only")
            let isMuxed = !(isAudioOnly || isVideoOnly)
            
            let choice = FormatChoice(
                id: formatID,
                description: line,
                isAudioOnly: isAudioOnly,
                isVideoOnly: isVideoOnly,
                isMuxed: isMuxed
            )
            results.append(choice)
        }
        
        // De-dupe by id (keep the first occurrence)
        var seen = Set<String>()
        let unique = results.filter { choice in
            if seen.contains(choice.id) { return false }
            seen.insert(choice.id)
            return true
        }
        
        // Sort by numeric part if available, otherwise lexical id
        func numeric(_ s: String) -> Int {
            Int(s.filter(\.isNumber)) ?? 0
        }
        
        let sorted = unique.sorted { a, b in
            let na = numeric(a.id)
            let nb = numeric(b.id)
            if na == 0 && nb == 0 {
                return a.id < b.id
            }
            return na < nb
        }
        
        return sorted
    }
    
    // MARK: - Start download with chosen format
    
    func startDownload(url: URL) async {
        print(#function, url, "selected format:", selectedFormatID ?? "nil (best)")
        
        do {
            let outputURL = try await download(url: url, formatString: selectedFormatID)
            
            export(url: outputURL)
            showProgress = false
            notify(body: "Finished")
        } catch YoutubeDLError.canceled {
            print(#function, "canceled")
        } catch {
            print(#function, error)
            if (url.host ?? "").hasSuffix("instagram.com") {
                webViewURL = url
                return
            }
            self.error = error
        }
    }
    
    // MARK: - Low-level yt-dlp wrapper (download)
    
    /// Actually runs yt-dlp with the correct -f or fallback and returns the final file URL
    func download(url: URL,
                  formatString: String?) async throws -> URL {
        progress.localizedDescription = NSLocalizedString("Extracting info", comment: "progress description")
        showProgress = true
        
        var files = [String]()
        var errorMessage: String?
        
        var argv: [String]
        
        if url.pathExtension == "mp4" {
            argv = [
                "-o", url.lastPathComponent
            ]
        } else {
            if let formatString, !formatString.isEmpty {
                argv = [
                    "-f", formatString,
                    "--merge-output-format", "mp4",
                    "--postprocessor-args", "Merger+ffmpeg:-c:v h264",
                    "-o", "%(title).200B.%(ext)s",
                ]
            } else {
                // Fallback: best
                argv = [
                    "-f", "bestvideo+bestaudio[ext=m4a]/best",
                    "--merge-output-format", "mp4",
                    "--postprocessor-args", "Merger+ffmpeg:-c:v h264",
                    "-o", "%(title).200B.%(ext)s",
                ]
            }
        }
        
        argv += [
            "--no-check-certificates",
            url.absoluteString,
        ]
        
        print(#function, "argv:", argv)
        
        try await yt_dlp(argv: argv) { dict in
            let status = String(dict["status"] ?? "")
            self.progress.localizedDescription = nil
            
            switch status {
            case "downloading":
                self.progress.kind = .file
                self.progress.fileOperationKind = .downloading
                if #available(iOS 16.0, *) {
                    if let tmpPath = String(dict["tmpfilename"] ?? "") {
                        self.progress.fileURL = URL(filePath: tmpPath)
                    }
                }
                
                self.progress.completedUnitCount = Int64(dict["downloaded_bytes"]!) ?? -1
                self.progress.totalUnitCount = Int64(
                    Double(dict["total_bytes"] ?? dict["total_bytes_estimate"] ?? Python.None) ?? -1
                )
                self.progress.throughput = Int(dict["speed"]!)
                self.progress.estimatedTimeRemaining = TimeInterval(dict["eta"]!)
                
            case "finished":
                if let filename = String(dict["filename"] ?? "") {
                    print(#function, "finished:", filename)
                    files.append(filename)
                } else {
                    print(#function, "finished but no filename in dict:", dict)
                }
                
            default:
                print(#function, "hook dict:", dict)
            }
        } log: { level, message in
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            print(#function, "yt-dlp [\(level)] \(trimmed)")
            if level == "error" {
                errorMessage = trimmed
            }
        } makeTranscodeProgressBlock: {
            self.progress.kind = nil
            self.progress.localizedDescription = NSLocalizedString("Transcoding...", comment: "progress description")
            self.progress.completedUnitCount = 0
            self.progress.totalUnitCount = 100
            
            let t0 = ProcessInfo.processInfo.systemUptime
            
            return { progress in
                print(#function, "transcode:", progress)
                let elapsed = ProcessInfo.processInfo.systemUptime - t0
                let speed = progress / elapsed
                let ETA = (1 - progress) / speed
                
                guard ETA.isFinite else { return }
                
                self.progress.completedUnitCount = Int64(progress * 100)
                self.progress.estimatedTimeRemaining = ETA
            }
        }
        
        if let errorMessage {
            throw NSError(domain: "App", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
        
        guard let path = files.first else {
            throw NSError(domain: "App", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "No output file from yt-dlp"])
        }
        
        if #available(iOS 16.0, *) {
            return URL(filePath: path)
        } else {
            return URL(fileURLWithPath: path)
        }
    }
    
    // MARK: - Transcode / mux (unchanged logic, concurrency-safe)
    
    func transcode(videoURL: URL,
                   transcodedURL: URL,
                   timeRange: Range<TimeInterval>?,
                   bitRate: Double?) async throws {
        progress.kind = nil
        progress.localizedDescription = NSLocalizedString("Transcoding...", comment: "progress description")
        progress.totalUnitCount = 100
        
        let t0 = ProcessInfo.processInfo.systemUptime
        
        let transcoder = Transcoder { progress in
            print(#function, "transcode:", progress)
            let elapsed = ProcessInfo.processInfo.systemUptime - t0
            let speed = progress / elapsed
            let ETA = (1 - progress) / speed
            
            guard ETA.isFinite else { return }
            
            self.progress.completedUnitCount = Int64(progress * 100)
            self.progress.estimatedTimeRemaining = ETA
        }
        
        let _: Int = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    try transcoder.transcode(from: videoURL,
                                             to: transcodedURL,
                                             timeRange: timeRange,
                                             bitRate: bitRate)
                    continuation.resume(returning: 0)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func mux(video videoURL: URL,
             audio audioURL: URL,
             out outputURL: URL,
             timeRange: Range<TimeInterval>?) async throws -> Bool {
        let t0 = ProcessInfo.processInfo.systemUptime
        
        let videoAsset = AVAsset(url: videoURL)
        let audioAsset = AVAsset(url: audioURL)
        
        guard let videoAssetTrack = videoAsset.tracks(withMediaType: .video).first,
              let audioAssetTrack = audioAsset.tracks(withMediaType: .audio).first else {
            print(#function,
                  videoAsset.tracks(withMediaType: .video),
                  audioAsset.tracks(withMediaType: .audio))
            return false
        }
        
        let composition = AVMutableComposition()
        let videoCompositionTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        let audioCompositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        
        do {
            try videoCompositionTrack?.insertTimeRange(
                CMTimeRange(start: .zero, duration: videoAssetTrack.timeRange.duration),
                of: videoAssetTrack,
                at: .zero
            )
            let range: CMTimeRange
            if let timeRange = timeRange {
                range = CMTimeRange(
                    start: CMTime(seconds: timeRange.lowerBound, preferredTimescale: 1),
                    end: CMTime(seconds: timeRange.upperBound, preferredTimescale: 1)
                )
            } else {
                range = CMTimeRange(start: .zero, duration: audioAssetTrack.timeRange.duration)
            }
            try audioCompositionTrack?.insertTimeRange(range, of: audioAssetTrack, at: .zero)
            print(#function, videoAssetTrack.timeRange, range)
        }
        catch {
            print(#function, error)
            return false
        }
        
        guard let session = AVAssetExportSession(asset: composition,
                                                 presetName: AVAssetExportPresetPassthrough) else {
            print(#function, "unable to init export session")
            return false
        }
        
        removeItem(at: outputURL)
        
        session.outputURL = outputURL
        session.outputFileType = .mp4
        print(#function, "merging...")
        
        return try await withCheckedThrowingContinuation { continuation in
            session.exportAsynchronously {
                print(#function, "finished merge", session.status.rawValue)
                print(#function, "took",
                      self.youtubeDL.downloader.dateComponentsFormatter.string(
                        from: ProcessInfo.processInfo.systemUptime - t0
                      ) ?? "?")
                if session.status == .completed {
                    if !self.youtubeDL.keepIntermediates {
                        removeItem(at: videoURL)
                        removeItem(at: audioURL)
                    }
                } else {
                    print(#function, session.error ?? "no error?")
                }
                
                continuation.resume(with: Result {
                    if let error = session.error { throw error }
                    return true
                })
            }
        }
    }
    
    // MARK: - Downloads list & documents folder
    
    func save(info: Info) throws -> URL {
        let title = info.safeTitle
        let fileManager = FileManager.default
        var url = URL(fileURLWithPath: title, relativeTo: try documentsDirectory())
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        
        // exclude from iCloud backup
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        
        let data = try JSONEncoder().encode(info)
        try data.write(to: url.appendingPathComponent("Info.json"))
        
        return url
    }
    
    func loadDownloads() throws -> [URL] {
        let keys: Set<URLResourceKey> = [.nameKey, .isDirectoryKey]
        let documents = try documentsDirectory()
        guard let enumerator = FileManager.default.enumerator(
            at: documents,
            includingPropertiesForKeys: Array(keys),
            options: .skipsHiddenFiles
        ) else { fatalError() }
        
        var urls = [URL]()
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            guard enumerator.level == 2,
                  url.lastPathComponent == "Info.json" else { continue }
            print(enumerator.level,
                  url.path.replacingOccurrences(of: documents.path, with: ""),
                  values.isDirectory ?? false ? "dir" : "file")
            urls.append(url.deletingLastPathComponent())
        }
        return urls
    }
    
    func documentsDirectory() throws -> URL {
        try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
    }
    
    // MARK: - Export
    
    func export(url: URL) {
        PHPhotoLibrary.shared().performChanges({
            _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }) { success, error in
            print(#function, success, error ?? "")
            DispatchQueue.main.async {
                self.error = error
            }
        }
    }
    
    func share() {
        // hook up a share sheet later if you want
    }
}

// MARK: - ANSI helpers

private extension AppModel {
    static let ansiEscapeRegex: NSRegularExpression = {
        // Matches CSI-style ANSI escape sequences that yt-dlp emits when color is enabled
        let pattern = "\u{001B}\\[[0-9;?]*[ -/]*[@-~]"
        return try! NSRegularExpression(pattern: pattern, options: [])
    }()
}

private extension String {
    func removingANSIEscapeSequences() -> String {
        let range = NSRange(startIndex..<endIndex, in: self)
        return AppModel.ansiEscapeRegex.stringByReplacingMatches(
            in: self,
            options: [],
            range: range,
            withTemplate: ""
        )
    }

    func removingControlCharacters() -> String {
        unicodeScalars
            .map { scalar in
                CharacterSet.controlCharacters.contains(scalar) ? " " : String(scalar)
            }
            .joined()
    }
}
