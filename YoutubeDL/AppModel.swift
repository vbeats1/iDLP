//
//  AppModel.swift
//  YoutubeDL
//
//  Based on original by Changbeom Ahn
//
//  Main application model that handles:
//  - Video/audio download from various platforms (YouTube, SoundCloud, Instagram, etc.)
//  - Format selection and quality options
//  - Merge operations (combining video + audio streams)
//  - Thumbnail and metadata embedding
//  - Progress tracking and logging
//  - File management and cleanup

import Foundation
@preconcurrency import PythonSupport
@preconcurrency import PythonKit
@preconcurrency import YoutubeDL
import Combine
import UIKit
import AVFoundation
import UserNotifications
import FFmpegSupport

// Global Python instance for accessing Python.None and other PythonKit features
let Python = PythonKit.Python

/// Main application model that manages downloads, formats, and UI state
/// All methods run on MainActor to ensure thread safety for UI updates
@MainActor
class AppModel: NSObject, ObservableObject {
    // MARK: - Published State (Observable Properties)
    
    @Published var url: URL?
    
    @Published var youtubeDL = YoutubeDL()
    
    @Published var showProgress = false
    var progress = Progress()
    
    @Published var error: Error?
    
    // Track merge status
    private var mergeInProgress = false
    
    // When Instagram falls back to WebView
    @Published var webViewURL: URL?
    
    // SoundCloud OAuth Token
    @Published var soundcloudOAuthToken: String? {
        didSet {
            UserDefaults.standard.set(soundcloudOAuthToken, forKey: "soundcloudOAuthToken")
        }
    }
    
    // Log messages for display in UI
    struct LogMessage: Identifiable, Hashable {
        let id = UUID()
        let message: String
        let level: LogLevel
        let timestamp: String
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        
        static func == (lhs: LogMessage, rhs: LogMessage) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    enum LogLevel: String, Hashable {
        case info = "info"
        case warning = "warning"
        case error = "error"
        case debug = "debug"
        case progress = "progress"
        case success = "success"
    }
    
    @Published var logMessages: [LogMessage] = []
    
    // MARK: - Predefined format options (for UI display - format is auto-selected by yt-dlp)
    
    struct FormatOption: Identifiable, Hashable {
        let id: String
        let displayName: String
        let formatString: String  // The -f argument for yt-dlp (not used anymore - auto-selected)
    }
    
    static let predefinedFormats: [FormatOption] = [
        FormatOption(id: "best", displayName: "Best Quality (Auto)", formatString: ""),
        FormatOption(id: "bestvideo", displayName: "Best Video Only", formatString: ""),
        FormatOption(id: "bestaudio", displayName: "Best Audio Only", formatString: ""),
        FormatOption(id: "worst", displayName: "Worst Quality", formatString: ""),
        FormatOption(id: "worstvideo", displayName: "Worst Video Only", formatString: ""),
        FormatOption(id: "worstaudio", displayName: "Worst Audio Only", formatString: ""),
        FormatOption(id: "720p", displayName: "720p", formatString: ""),
        FormatOption(id: "480p", displayName: "480p", formatString: ""),
        FormatOption(id: "360p", displayName: "360p", formatString: ""),
        FormatOption(id: "mp4", displayName: "MP4 Format", formatString: ""),
    ]
    
    @Published var selectedFormatID: String? = "best"  // For UI display only - format is auto-selected
    
    // MARK: - Init
    
    override init() {
        super.init()
        youtubeDL.downloadsDirectory = try! self.documentsDirectory()
        
        // Load OAuth token from UserDefaults if it exists
        soundcloudOAuthToken = UserDefaults.standard.string(forKey: "soundcloudOAuthToken")
        
    }
    
    /// Add a log message to the UI log
    func addLog(_ message: String, level: LogLevel = .info) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logMessages.append(LogMessage(message: message, level: level, timestamp: timestamp))
        // Keep only last 100 log messages
        if logMessages.count > 100 {
            logMessages.removeFirst()
        }
    }
    
    // Track last logged progress to avoid spam
    private var lastLoggedProgress: (completed: Int64, total: Int64, percent: Int)?
    
    /// Add progress info to log (only when it changes significantly)
    func addProgressLog(description: String?, completed: Int64, total: Int64) {
        if let description = description, !description.isEmpty {
            // Only log description if it's different from the last one
            if let lastMessage = logMessages.last, lastMessage.message != description {
                addLog(description, level: .progress)
            }
        }
        
        if total > 0 {
            let percent = Int((Double(completed) / Double(total)) * 100)
            
            // Only log if percent changed by at least 1% or if it's the first time
            if let last = lastLoggedProgress {
                if abs(percent - last.percent) < 1 && completed == last.completed {
                    return // Skip duplicate
                }
            }
            
            let completedMB = Double(completed) / 1_000_000.0
            let totalMB = Double(total) / 1_000_000.0
            addLog("Progress: \(String(format: "%.1f", completedMB)) MB / \(String(format: "%.1f", totalMB)) MB (\(percent)%)", level: .progress)
            lastLoggedProgress = (completed, total, percent)
        }
    }
    
    // MARK: - Download Management
    
    /// Reset all download-related state for a fresh download
    private func resetDownloadState() {
        showProgress = false
        mergeInProgress = false
        lastLoggedProgress = nil
        error = nil
        // Note: webViewURL is NOT reset here - it's managed separately for Instagram fallback
        
        // Reset progress object
        progress = Progress()
        progress.completedUnitCount = 0
        progress.totalUnitCount = 0
        progress.localizedDescription = nil
        progress.kind = nil
        progress.fileOperationKind = nil
        if #available(iOS 16.0, *) {
            progress.fileURL = nil
        }
        progress.throughput = nil
        progress.estimatedTimeRemaining = nil
    }
    
    /// Full reset - recreates yt-dlp instance and clears all state
    /// Use this when downloads are failing to ensure a completely fresh start
    func fullReset() {
        addLog("🔄 Performing full reset...", level: .info)
        
        // Recreate yt-dlp instance (fresh Python process)
        youtubeDL = YoutubeDL()
        
        // Reset downloads directory
        if let downloadsDir = try? self.documentsDirectory() {
            youtubeDL.downloadsDirectory = downloadsDir
        }
        
        // Reset all state
        resetDownloadState()
        
        // Clear log messages (optional - you might want to keep them)
        // logMessages.removeAll()
        
        // Clear URL
        url = nil
        
        // Clear webViewURL
        webViewURL = nil
        
        addLog("✅ Full reset complete - ready for new download", level: .success)
    }
    
    /// Starts a download for the given URL using the selected format
    /// Handles special cases:
    /// - SoundCloud URLs with OAuth token (uses high-quality handler)
    /// - Regular URLs (uses standard download handler)
    /// - Instagram URLs (may fall back to WebView)
    /// 
    /// - Parameter url: The media URL to download
    /// 
    /// After download completes:
    /// - Exports file to Documents folder
    /// - Shows notification
    /// - Opens Files app to show downloaded file
    func startDownload(url: URL) async {
        // Reset all state for a fresh download
        resetDownloadState()
        
        // Recreate yt-dlp instance for each download to ensure fresh Python process
        youtubeDL = YoutubeDL()
        if let downloadsDir = try? self.documentsDirectory() {
            youtubeDL.downloadsDirectory = downloadsDir
        }
        // Check if this is a SoundCloud link - always use dedicated handler
        let isSoundCloud = url.host?.contains("soundcloud.com") ?? false
        
        if isSoundCloud {
            // Use dedicated SoundCloud handler (automatically selected for SoundCloud links)
            do {
                let outputURL = try await downloadSoundCloud(url: url)
                
                // Wait a moment to ensure file is fully written
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                addLog("Download completed: \(outputURL.lastPathComponent)", level: .success)
                self.export(url: outputURL)
                showProgress = false
                notify(body: "Download complete: \(outputURL.lastPathComponent)")
                addLog("✅ Download process finished successfully", level: .success)
                // Reset state after successful download
                resetDownloadState()
            } catch {
                print(#function, error)
                addLog("Download error: \(error.localizedDescription)", level: .error)
                // Clean up temp files on error
                if let downloadsDir = try? self.documentsDirectory() {
                    self.cleanupTempFiles(in: downloadsDir)
                }
                self.error = error
                showProgress = false
                resetDownloadState()
                addLog("❌ Download process finished with errors", level: .error)
            }
            return
        }
        
        // Format selection is now handled automatically by yt-dlp
        // We pass nil to let yt-dlp pick the best format
        do {
            addLog("📥 Initiating download...", level: .info)
            let outputURL = try await download(url: url, formatString: nil)
            
            // Wait a moment to ensure file is fully written
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            addLog("Download completed: \(outputURL.lastPathComponent)", level: .success)
            self.export(url: outputURL)
            showProgress = false
            notify(body: "Download complete: \(outputURL.lastPathComponent)")
            // Reset state after successful download
            resetDownloadState()
        } catch YoutubeDLError.canceled {
            print(#function, "canceled")
            addLog("Download canceled", level: .warning)
            // Clean up temp files on cancel
            if let downloadsDir = try? self.documentsDirectory() {
                self.cleanupTempFiles(in: downloadsDir)
            }
            showProgress = false
            resetDownloadState()
            addLog("⚠️ Download process finished - canceled by user", level: .warning)
        } catch {
            print(#function, error)
            addLog("Download error: \(error.localizedDescription)", level: .error)
            // Clean up temp files on error
            if let downloadsDir = try? self.documentsDirectory() {
                self.cleanupTempFiles(in: downloadsDir)
            }
            if (url.host ?? "").hasSuffix("instagram.com") {
                webViewURL = url
                addLog("⚠️ Download process finished - Instagram fallback to WebView", level: .warning)
                // Don't reset state here - WebView will handle the download
                return
            }
            self.error = error
            showProgress = false
            resetDownloadState()
            addLog("❌ Download process finished with errors", level: .error)
        }
    }
    
    // MARK: - SoundCloud-Specific Download Handler
    
    /// Dedicated handler for SoundCloud downloads
    /// 
    /// SoundCloud handler that:
    /// - Automatically detects SoundCloud links and uses this handler
    /// - Uses OAuth authentication if available (unlocks higher quality formats)
    /// - Downloads files as-is without conversion (no fixup/post-processing)
    /// - Adds metadata and thumbnails
    /// - Uses ffmpeg fallback for thumbnail embedding (avoids freezing issues)
    /// 
    /// - Parameter url: The SoundCloud track URL
    /// - Returns: URL of the downloaded audio file
    /// - Throws: Error if download fails
    func downloadSoundCloud(url: URL) async throws -> URL {
        addLog("🎵 SoundCloud link detected - using dedicated SoundCloud handler", level: .info)
        addLog("📋 Step 1: Checking OAuth authentication...", level: .info)
        
        // Get OAuth token from settings (optional - will warn if missing)
        let token = soundcloudOAuthToken
        let hasOAuthToken = token != nil && !(token?.isEmpty ?? true)
        
        if hasOAuthToken {
            addLog("✅ Step 1: OAuth token found in settings", level: .success)
            addLog("🔑 Using SoundCloud OAuth token from settings", level: .info)
            print(#function, "Token:", token!)
        } else {
            addLog("⚠️ Step 1: No OAuth token found - downloading standard quality", level: .warning)
            addLog("💡 Add OAuth token in Settings for higher quality downloads", level: .info)
        }
        
        addLog("📋 Step 2: Preparing download arguments...", level: .info)
        
        // Build argv for SoundCloud download
        // Key points:
        // - Use OAuth if available (unlocks higher quality)
        // - Download as-is (no fixup, no conversion)
        // - Add metadata and thumbnails
        var argv: [String] = []
        
        // Add OAuth authentication if token is available
        if hasOAuthToken, let token = token {
            argv += [
                "--username", "oauth",
                "--password", token,
                "--add-header", "Authorization: OAuth \(token)",
                "--add-header", "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                "--extractor-args", "soundcloud:oauth_token=\(token)",
            ]
        }
        
        // Add download arguments
        // Note: No format flag - let yt-dlp automatically pick the best format
        argv += [
            // Write thumbnail file (for fallback if embedding fails)
            "--write-thumbnail",
            // Embed thumbnail directly (faster than ffmpeg fallback)
            "--embed-thumbnail",
            // Output filename
            "-o", "%(title).200B.%(ext)s",
            // Continue on errors (including thumbnail embedding failures)
            "--ignore-errors",
            // Network settings
            "--no-check-certificates",
            // URL
            url.absoluteString,
        ]
        
        // Note: We intentionally do NOT use:
        // - -f format flag (let yt-dlp pick best automatically)
        // - --add-metadata (removed - no metadata handling)
        // - --fixup (let yt-dlp use default behavior, or remove it to avoid conversion)
        // - --merge-output-format (SoundCloud is audio-only, no merging needed)
        // - --postprocessor-args (no conversion needed)
        
        print(#function, "SoundCloud download argv:", argv)
        Task { @MainActor in
            self.addLog("✅ Step 2: Download arguments prepared", level: .success)
            self.addLog("🚀 Step 3: Starting SoundCloud download...", level: .info)
            if hasOAuthToken {
                self.addLog("🔐 OAuth authentication enabled (unlocks high quality)", level: .info)
                self.addLog("📋 Format: Auto-selected by yt-dlp (best available)", level: .info)
            } else {
                self.addLog("⚠️ No OAuth token - standard quality only", level: .warning)
                self.addLog("📋 Format: Auto-selected by yt-dlp", level: .info)
            }
            self.addLog("🖼️ Thumbnail: Will be embedded by yt-dlp (with ffmpeg fallback if needed)", level: .info)
            self.addLog("📝 Metadata: Skipped (thumbnail only)", level: .info)
        }
        
        // Use the same download logic but with SoundCloud-specific args
        return try await downloadWithArgs(url: url, argv: argv)
    }
    
    // MARK: - Core Download Function
    
    /// Main download function that runs yt-dlp without format flags
    /// 
    /// This function handles YouTube and other platforms (NOT SoundCloud - SoundCloud uses downloadSoundCloud()).
    /// 
    /// This function:
    /// - Lets yt-dlp automatically pick the best format (no -f flag)
    /// - Configures merge output format (MP4) for video+audio downloads
    /// - Sets up thumbnail writing (will be embedded via ffmpeg fallback)
    /// - Uses --fixup never to avoid container conversion issues
    /// - Calls downloadWithArgs to execute the actual download
    /// 
    /// - Parameters:
    ///   - url: The media URL to download (YouTube, Instagram, etc. - NOT SoundCloud)
    ///   - formatString: Ignored - yt-dlp will auto-select best format
    /// - Returns: URL of the final downloaded/merged file
    /// - Throws: Error if download fails
    func download(url: URL,
                  formatString: String?) async throws -> URL {
        mergeInProgress = false  // Reset merge status
        progress.localizedDescription = NSLocalizedString("Extracting info", comment: "progress description")
        showProgress = true
        
        Task { @MainActor in
            self.addLog("🚀 Starting download...", level: .info)
            self.addLog("📋 Format: Auto-selected by yt-dlp (best available)", level: .info)
            self.addLog("🖼️ Thumbnail: Will be embedded by yt-dlp (with ffmpeg fallback if needed)", level: .info)
            self.addLog("📝 Metadata: Skipped (thumbnail only)", level: .info)
        }
        
        var argv: [String]
        
        if url.pathExtension == "mp4" {
            argv = [
                "-o", url.lastPathComponent
            ]
        } else {
            // No format flag - let yt-dlp automatically pick the best format
            // yt-dlp will handle merging video+audio automatically if needed
            argv = [
                // Disable all fixup post-processors (including FixupM4a) to avoid container conversion issues
                "--fixup", "never",
                // Write thumbnail file (for fallback if embedding fails)
                "--write-thumbnail",
                // Embed thumbnail directly (faster than ffmpeg fallback)
                "--embed-thumbnail",
                "--ignore-errors",  // Continue even if post-processing fails (including thumbnail embedding)
                "-o", "%(title).200B.%(ext)s",
            ]
        }
        
        // Note: SoundCloud links are handled by downloadSoundCloud() and won't reach this function
        // This function handles YouTube and other platforms
        
        argv += [
            "--no-check-certificates",
            url.absoluteString,
        ]
        
        print(#function, "argv:", argv)
        Task { @MainActor in
            self.addLog("✅ Step 1: Download arguments prepared", level: .success)
            self.addLog("🔧 Step 2: Running yt-dlp with auto-format selection...", level: .info)
        }
        
        return try await downloadWithArgs(url: url, argv: argv)
    }
    
    /// Internal helper that runs yt-dlp with provided argv and handles file finding
    /// This is the core download function that:
    /// - Wraps yt-dlp calls with timeout protection (15 minutes)
    /// - Monitors merge progress and detects stuck operations
    /// - Handles file discovery after download completes
    /// - Manages temp file cleanup
    /// 
    /// - Parameters:
    ///   - url: The source URL to download from
    ///   - argv: Command-line arguments to pass to yt-dlp
    /// - Returns: URL of the final downloaded/merged file
    /// - Throws: NSError if download fails or times out
    private func downloadWithArgs(url: URL, argv: [String]) async throws -> URL {
        var files = [String]()  // Track files created during download
        var errorMessage: String?  // Capture any error messages from yt-dlp
        var mergedFilename: String?  // Track the final merged filename from logs
        var mergeStartTime: Date?  // Track when merge started for timeout warnings
        var downloadFinished = false  // Track when download phase completes
        var processingStartTime: Date?  // Track when processing (merge/thumbnail) starts
        var downloadedFileSize: Int64 = 0  // Track file size for dynamic timeout calculation
        var processingTimeoutExceeded = false  // Flag to track if processing timeout was exceeded
        
        // Use a very long timeout for download phase (2 hours) to allow for slow internet
        // Processing timeout will be calculated dynamically based on file size after download finishes
        Task { @MainActor in
            self.addLog("⏱️ Download timeout: 2 hours (allows for slow internet)", level: .info)
            self.addLog("⏱️ Processing timeout: Dynamic (10s for <100MB, 500s for ≥100MB)", level: .info)
        }
        
        // Calculate processing timeout based on file size
        // 10 seconds for files under 100MB, 500 seconds for files 100MB or larger
        func getProcessingTimeout(fileSize: Int64) -> TimeInterval {
            if fileSize < 100 * 1024 * 1024 { // Less than 100 MB
                return 10.0
            } else {
                return 500.0
            }
        }
        do {
            // Use 2 hour timeout for download phase - this won't affect slow downloads
            try await withTimeout(seconds: 7200) { // 2 hours for download phase
                Task { @MainActor in
                    self.addLog("🔍 Step 3: Extracting video/audio information...", level: .info)
                }
                return try await yt_dlp(argv: argv) { dict in
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
                
                // Add progress to log with detailed info
                Task { @MainActor in
                    let completed = self.progress.completedUnitCount
                    let total = self.progress.totalUnitCount
                    let speed = self.progress.throughput ?? 0
                    let eta = self.progress.estimatedTimeRemaining ?? 0
                    
                    if total > 0 {
                        let percent = Int((Double(completed) / Double(total)) * 100)
                        let speedMB = Double(speed) / 1_000_000.0
                        let etaMin = Int(eta) / 60
                        let etaSec = Int(eta) % 60
                        self.addLog("⬇️ Downloading: \(percent)% | Speed: \(String(format: "%.1f", speedMB)) MB/s | ETA: \(etaMin)m \(etaSec)s", level: .progress)
                    }
                    self.addProgressLog(
                        description: "Downloading...",
                        completed: completed,
                        total: total
                    )
                }
                
            case "finished":
                // Mark download as finished - processing timeout will now apply
                if !downloadFinished {
                    downloadFinished = true
                    processingStartTime = Date()
                    // Get file size from progress for timeout calculation
                    downloadedFileSize = self.progress.totalUnitCount > 0 ? self.progress.totalUnitCount : 0
                    let processingTimeout = getProcessingTimeout(fileSize: downloadedFileSize)
                    let timeoutMinutes = Int(processingTimeout) / 60
                    let timeoutSeconds = Int(processingTimeout) % 60
                    Task { @MainActor in
                        if downloadedFileSize > 0 {
                            let fileSizeMB = Double(downloadedFileSize) / (1024 * 1024)
                            self.addLog("✅ Download phase completed - file size: \(String(format: "%.2f", fileSizeMB)) MB", level: .success)
                        }
                        self.addLog("⏱️ Processing timeout: \(timeoutMinutes)m \(timeoutSeconds)s (based on file size)", level: .info)
                    }
                }
                if let filename = String(dict["filename"] ?? "") {
                    print(#function, "finished:", filename)
                    files.append(filename)
                    Task { @MainActor in
                        self.addLog("✅ Download finished: \(filename)", level: .success)
                    }
                } else {
                    print(#function, "finished but no filename in dict:", dict)
                    Task { @MainActor in
                        self.addLog("✅ Download finished (processing filename...)", level: .success)
                    }
                }
                
            default:
                print(#function, "hook dict:", dict)
                if let status = status, !status.isEmpty {
                    Task { @MainActor in
                        self.addLog("ℹ️ Status: \(status)", level: .info)
                    }
                }
            }
        } log: { level, message in
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            print(#function, "yt-dlp [\(level)] \(trimmed)")
            
            // Check processing timeout (only after download finishes)
            if downloadFinished, let processingStart = processingStartTime {
                let processingTimeout = getProcessingTimeout(fileSize: downloadedFileSize)
                let processingElapsed = Date().timeIntervalSince(processingStart)
                if processingElapsed > processingTimeout {
                    processingTimeoutExceeded = true
                    Task { @MainActor in
                        self.addLog("❌ [PROCESSING] TIMEOUT: Processing phase exceeded \(Int(processingTimeout)) seconds", level: .error)
                        self.addLog("💡 This usually means merge/thumbnail embedding is stuck", level: .info)
                    }
                } else if processingElapsed > processingTimeout * 0.8 { // 80% of timeout warning
                    Task { @MainActor in
                        let elapsedSeconds = Int(processingElapsed)
                        self.addLog("⚠️ [PROCESSING] WARNING: Processing has been running for \(elapsedSeconds) seconds (timeout: \(Int(processingTimeout))s)", level: .warning)
                    }
                }
            }
            
            // Check if merge has been running too long without progress
            if let mergeStart = mergeStartTime, self.mergeInProgress {
                let mergeElapsed = Date().timeIntervalSince(mergeStart)
                if mergeElapsed > 600 { // 10 minutes
                    Task { @MainActor in
                        self.addLog("⚠️ [MERGE] WARNING: Merge has been running for \(Int(mergeElapsed/60)) minutes - may be stuck", level: .warning)
                    }
                }
            }
            
            // Enhanced logging with step identification
            Task { @MainActor in
                let logLevel: LogLevel = {
                    switch level.lowercased() {
                    case "error": return .error
                    case "warning", "warn": return .warning
                    case "debug": return .debug
                    default: return .info
                    }
                }()
                
                // Add step prefixes for better visibility
                var logMessage = trimmed
                if trimmed.contains("[ExtractInfo]") || trimmed.contains("Extracting") {
                    logMessage = "🔍 " + trimmed
                } else if trimmed.contains("[Download]") {
                    logMessage = "⬇️ " + trimmed
                } else if trimmed.contains("[Merger]") || trimmed.contains("Merging") {
                    logMessage = "🔄 " + trimmed
                } else if trimmed.contains("[Thumbnail]") || trimmed.contains("thumbnail") {
                    logMessage = "🖼️ " + trimmed
                } else if trimmed.contains("[info]") {
                    logMessage = "ℹ️ " + trimmed
                } else if trimmed.contains("ERROR") || trimmed.contains("error") {
                    logMessage = "❌ " + trimmed
                } else if trimmed.contains("WARNING") || trimmed.contains("warning") {
                    logMessage = "⚠️ " + trimmed
                }
                
                self.addLog(logMessage, level: logLevel)
            }
            
            // Parse thumbnail embedding messages from yt-dlp
            if trimmed.contains("[EmbedThumbnail]") {
                // If thumbnail embedding starts and download hasn't been marked finished, mark it now
                if !downloadFinished {
                    downloadFinished = true
                    processingStartTime = Date()
                    downloadedFileSize = self.progress.totalUnitCount > 0 ? self.progress.totalUnitCount : 0
                    let processingTimeout = getProcessingTimeout(fileSize: downloadedFileSize)
                    let timeoutMinutes = Int(processingTimeout) / 60
                    let timeoutSeconds = Int(processingTimeout) % 60
                    Task { @MainActor in
                        self.addLog("✅ Download phase completed (detected via thumbnail embedding)", level: .success)
                        self.addLog("⏱️ Processing timeout: \(timeoutMinutes)m \(timeoutSeconds)s (based on file size)", level: .info)
                    }
                }
                if trimmed.contains("Adding thumbnail") || trimmed.contains("Embedding thumbnail") {
                    Task { @MainActor in
                        self.addLog("🖼️ yt-dlp: Attempting to embed thumbnail/cover art...", level: .info)
                    }
                } else if trimmed.contains("error") || trimmed.contains("failed") || trimmed.contains("ERROR") {
                    Task { @MainActor in
                        self.addLog("⚠️ yt-dlp thumbnail embedding issue: \(trimmed)", level: .warning)
                        self.addLog("ℹ️ Will use ffmpeg fallback after download completes", level: .info)
                    }
                } else if trimmed.contains("successfully") || trimmed.contains("embedded") {
                    Task { @MainActor in
                        self.addLog("✅ yt-dlp: Thumbnail embedded successfully", level: .success)
                    }
                }
            }
            
            // Parse merge messages with detailed logging
            // yt-dlp uses [Merger] prefix for merge operations
            if trimmed.contains("[Merger]") || trimmed.contains("Merging") || trimmed.contains("merging") {
                print("🟡 [MERGE LOG] Merge-related message: \(trimmed)")
                Task { @MainActor in
                    self.addLog("📋 Merge log: \(trimmed)", level: .info)
                }
                
                if trimmed.contains("Merging formats into") || trimmed.contains("merging formats") {
                    print("🟡 [MERGE LOG] Merge started!")
                    mergeStartTime = Date()
                    // If download hasn't finished yet, mark processing as starting now
                    // (merge can start before we see "finished" status in some cases)
                    if !downloadFinished {
                        downloadFinished = true
                        processingStartTime = Date()
                        downloadedFileSize = self.progress.totalUnitCount > 0 ? self.progress.totalUnitCount : 0
                        let processingTimeout = getProcessingTimeout(fileSize: downloadedFileSize)
                        let timeoutMinutes = Int(processingTimeout) / 60
                        let timeoutSeconds = Int(processingTimeout) % 60
                        Task { @MainActor in
                            self.addLog("✅ Download phase completed (detected via merge start)", level: .success)
                            self.addLog("⏱️ Processing timeout: \(timeoutMinutes)m \(timeoutSeconds)s (based on file size)", level: .info)
                        }
                    }
                    Task { @MainActor in
                        self.mergeInProgress = true
                        self.progress.localizedDescription = NSLocalizedString("Merging video and audio...", comment: "progress description")
                        self.addLog("🔄 [MERGE] Starting merge: combining video and audio streams", level: .info)
                        self.addLog("⏱️ [MERGE] Merge timeout: 10 minutes (will abort if stuck)", level: .info)
                    }
                    if let startRange = trimmed.range(of: "\""),
                       let endRange = trimmed.range(of: "\"", range: startRange.upperBound..<trimmed.endIndex) {
                        let filename = String(trimmed[startRange.upperBound..<endRange.lowerBound])
                        mergedFilename = filename
                        print("✅ [MERGE LOG] Detected merged filename: \(filename)")
                        Task { @MainActor in
                            self.addLog("📝 [MERGE] Target output file: \(filename)", level: .info)
                        }
                    }
                } else if trimmed.contains("has already been merged") || 
                          trimmed.contains("Deleting original file") ||
                          trimmed.contains("Post-process") ||
                          trimmed.contains("finished") ||
                          trimmed.contains("Merge complete") {
                    print("✅ [MERGE LOG] Merge completion detected: \(trimmed)")
                    Task { @MainActor in
                        self.mergeInProgress = false
                        self.progress.localizedDescription = NSLocalizedString("Finalizing...", comment: "progress description")
                        self.addLog("✅ [MERGE] Merge completed successfully!", level: .success)
                    }
                } else if trimmed.contains("ffmpeg") || trimmed.contains("FFmpeg") {
                    // Log ffmpeg merge progress
                    Task { @MainActor in
                        self.addLog("⚙️ [MERGE] FFmpeg processing: \(trimmed)", level: .info)
                    }
                }
            }
            
            // Check for ffmpeg merge progress indicators
            if trimmed.contains("frame=") || trimmed.contains("fps=") || trimmed.contains("bitrate=") {
                // This is ffmpeg progress output during merge
                Task { @MainActor in
                    self.addLog("⚙️ [MERGE] FFmpeg: \(trimmed)", level: .progress)
                }
            }
            
            // Also check for completion indicators in info messages
            if level == "info" && (trimmed.contains("Deleting original file") || 
                                   trimmed.contains("has already been merged") ||
                                   trimmed.contains("Post-processing") ||
                                   trimmed.contains("WARNING:") && trimmed.contains("merge")) {
                print("✅ [MERGE LOG] Merge completion indicator in info: \(trimmed)")
                Task { @MainActor in
                    self.mergeInProgress = false
                    self.addLog("✅ [MERGE] Merge process complete: \(trimmed)", level: .success)
                }
            }
            
            // Log any error during merge
            if level == "error" && (trimmed.contains("Merger") || trimmed.contains("merge") || trimmed.contains("Merge")) {
                Task { @MainActor in
                    self.addLog("❌ [MERGE] Error during merge: \(trimmed)", level: .error)
                }
            }
            
            if level == "error" {
                errorMessage = trimmed
            }
        } makeTranscodeProgressBlock: {
            Task { @MainActor in
                self.progress.kind = nil
                self.progress.localizedDescription = NSLocalizedString("Transcoding...", comment: "progress description")
                self.progress.completedUnitCount = 0
                self.progress.totalUnitCount = 100
            }
            
            let t0 = ProcessInfo.processInfo.systemUptime
            
            return { progress in
                print(#function, "transcode:", progress)
                let elapsed = ProcessInfo.processInfo.systemUptime - t0
                let speed = progress / elapsed
                let ETA = (1 - progress) / speed
                
                guard ETA.isFinite else { return }
                
                Task { @MainActor in
                    self.progress.completedUnitCount = Int64(progress * 100)
                    self.progress.estimatedTimeRemaining = ETA
                }
            }
        }
            }
            
            // Check if processing timeout was exceeded (set in log closure)
            if processingTimeoutExceeded {
                let processingTimeout = getProcessingTimeout(fileSize: downloadedFileSize)
                // Clean up temp files on timeout
                if let downloadsDir = try? self.documentsDirectory() {
                    self.cleanupTempFiles(in: downloadsDir)
                }
                if mergeInProgress {
                    Task { @MainActor in
                        self.addLog("❌ [MERGE] TIMEOUT: Merge operation timed out after \(Int(processingTimeout)) seconds", level: .error)
                        self.addLog("💡 [MERGE] This usually means FFmpeg is stuck. Try a different video or format.", level: .info)
                        self.addLog("❌ Download process finished - timeout error", level: .error)
                    }
                    throw NSError(domain: "App", code: 3,
                                  userInfo: [NSLocalizedDescriptionKey: "Merge operation timed out after \(Int(processingTimeout)) seconds. FFmpeg may be stuck."])
                } else {
                    Task { @MainActor in
                        self.addLog("❌ [PROCESSING] TIMEOUT: Processing phase timed out after \(Int(processingTimeout)) seconds", level: .error)
                        self.addLog("💡 This usually means thumbnail embedding or post-processing is stuck", level: .info)
                        self.addLog("❌ Download process finished - timeout error", level: .error)
                    }
                    throw NSError(domain: "App", code: 3,
                                  userInfo: [NSLocalizedDescriptionKey: "Processing phase timed out after \(Int(processingTimeout)) seconds. Post-processing may be stuck."])
                }
            }
            
            } catch is TimeoutError {
            // Clean up temp files on timeout
            if let downloadsDir = try? self.documentsDirectory() {
                self.cleanupTempFiles(in: downloadsDir)
            }
            
            // Timeout occurred - check which phase we're in
            if downloadFinished {
                // Processing phase timeout (dynamic based on file size)
                let processingTimeout = getProcessingTimeout(fileSize: downloadedFileSize)
                if mergeInProgress {
                    Task { @MainActor in
                        self.addLog("❌ [MERGE] TIMEOUT: Merge operation timed out after \(Int(processingTimeout)) seconds", level: .error)
                        self.addLog("💡 [MERGE] This usually means FFmpeg is stuck. Try a different video or format.", level: .info)
                        self.addLog("❌ Download process finished - timeout error", level: .error)
                    }
                    throw NSError(domain: "App", code: 3,
                                  userInfo: [NSLocalizedDescriptionKey: "Merge operation timed out after \(Int(processingTimeout)) seconds. FFmpeg may be stuck."])
                } else {
                    Task { @MainActor in
                        self.addLog("❌ [PROCESSING] TIMEOUT: Processing phase timed out after \(Int(processingTimeout)) seconds", level: .error)
                        self.addLog("💡 This usually means thumbnail embedding or post-processing is stuck", level: .info)
                        self.addLog("❌ Download process finished - timeout error", level: .error)
                    }
                    throw NSError(domain: "App", code: 3,
                                  userInfo: [NSLocalizedDescriptionKey: "Processing phase timed out after \(Int(processingTimeout)) seconds. Post-processing may be stuck."])
                }
            } else {
                // Download phase timeout (2 hours - very unlikely unless truly stuck)
                Task { @MainActor in
                    self.addLog("❌ [DOWNLOAD] TIMEOUT: Download operation timed out after 2 hours", level: .error)
                    self.addLog("💡 This is unusual - check your internet connection", level: .info)
                    self.addLog("❌ Download process finished - timeout error", level: .error)
                }
                throw NSError(domain: "App", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "Download operation timed out after 2 hours. Check your internet connection."])
            }
        }
        
        if let errorMessage {
            // Don't fail the download if only thumbnail embedding failed
            // yt-dlp will continue anyway with --ignore-errors
            // We'll use ffmpeg fallback after download completes
            if errorMessage.contains("EmbedThumbnail") || errorMessage.contains("JSONDecodeError") || errorMessage.contains("Expecting value") {
                Task { @MainActor in
                    self.addLog("⚠️ yt-dlp thumbnail embedding failed, but download succeeded", level: .warning)
                    self.addLog("ℹ️ Will attempt ffmpeg fallback after download completes", level: .info)
                }
                // Don't throw - continue with the download
            } else {
                // Clean up temp files on error before throwing
                if let downloadsDir = try? self.documentsDirectory() {
                    self.cleanupTempFiles(in: downloadsDir)
                }
                throw NSError(domain: "App", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: errorMessage])
            }
        }
        
        // Try to find the final file: prefer merged filename, then files array, then search directory
        var finalPath: String?
        
        if let mergedFilename = mergedFilename {
            // Use the merged filename from the log
            let downloadsDir = try self.documentsDirectory()
            let fullPath = downloadsDir.appendingPathComponent(mergedFilename).path
            if FileManager.default.fileExists(atPath: fullPath) {
                finalPath = fullPath
                print(#function, "Using merged filename:", fullPath)
            }
        }
        
        // Fallback to files array
        if finalPath == nil, let firstFile = files.first {
            finalPath = firstFile
            print(#function, "Using file from hook:", firstFile)
        }
        
        // Last resort: search for the most recent .mp4 file in downloads directory
        if finalPath == nil {
            let downloadsDir = try self.documentsDirectory()
            // Use nonisolated helper function for file enumeration
            let mp4Files = await findMP4Files(in: downloadsDir)
            // Get the most recently modified file
            if let mostRecent = mp4Files.max(by: { $0.1 < $1.1 }) {
                finalPath = mostRecent.0.path
                print(#function, "Found most recent MP4:", finalPath!)
            }
        }
        
        guard let path = finalPath else {
            Task { @MainActor in
                self.addLog("❌ Error: No output file found from yt-dlp", level: .error)
            }
            throw NSError(domain: "App", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "No output file from yt-dlp"])
        }
        
        Task { @MainActor in
            self.addLog("✅ Found output file: \((path as NSString).lastPathComponent)", level: .success)
        }
        
        // Wait for file to be fully written (check file size stability)
        let fileURL: URL
        if #available(iOS 16.0, *) {
            fileURL = URL(filePath: path)
        } else {
            fileURL = URL(fileURLWithPath: path)
        }
        
        let downloadsDir = try self.documentsDirectory()
        let fileManager = FileManager.default
        
        print("🔵 [MERGE WAIT] Starting file wait check")
        print("🔵 [MERGE WAIT] Final file path: \(path)")
        print("🔵 [MERGE WAIT] Merge in progress flag: \(mergeInProgress)")
        
        // If merge is in progress, also check for .temp.mp4 file
        if mergeInProgress {
            Task { @MainActor in
                self.progress.localizedDescription = NSLocalizedString("Merging video and audio...", comment: "progress description")
                self.addLog("🔄 [MERGE] Starting merge process...", level: .info)
            }
            
            // Wait for either the final file or the temp file to appear
            let tempPath = path.replacingOccurrences(of: ".mp4", with: ".temp.mp4")
            print("🟡 [MERGE WAIT] Temp file path: \(tempPath)")
            Task { @MainActor in
                self.addLog("📁 [MERGE] Monitoring temp file: \((tempPath as NSString).lastPathComponent)", level: .info)
                self.addLog("⏱️ [MERGE] Stuck detection: Will warn if no progress for 2 minutes", level: .info)
            }
            
            var foundFile = false
            var lastTempSize: Int64 = 0
            var lastFinalSize: Int64 = 0
            var initialTempSize: Int64 = 0
            var maxExpectedSize: Int64 = 0
            var stableCount = 0
            var lastUpdateTime = Date()
            var lastSizeChangeTime = Date()
            var stuckWarningShown = false
            
            // Wait up to 10 minutes (6000 iterations * 0.1s) for merge to complete
            for i in 0..<6000 {
                let seconds = i / 10
                let elapsed = Date().timeIntervalSince(lastUpdateTime)
                
                // Check if final file exists
                let finalExists = fileManager.fileExists(atPath: path)
                let tempExists = fileManager.fileExists(atPath: tempPath)
                
                // Check temp file - if it exists, merge is still happening
                if tempExists {
                    if let attributes = try? fileManager.attributesOfItem(atPath: tempPath),
                       let tempSize = attributes[.size] as? Int64 {
                        
                        // Initialize expected size on first detection
                        if initialTempSize == 0 && tempSize > 0 {
                            initialTempSize = tempSize
                            // Estimate max size (usually temp file grows, then final file is created)
                            maxExpectedSize = tempSize * 2 // Rough estimate
                            let formattedSize = await MainActor.run { self.formatBytes(tempSize) }
                            Task { @MainActor in
                                self.addLog("📊 [MERGE] Initial temp file size: \(formattedSize)", level: .info)
                            }
                        }
                        
                        if tempSize != lastTempSize {
                            // File is growing - merge in progress
                            let progressBar = await MainActor.run { self.generateProgressBar(current: tempSize, total: maxExpectedSize > 0 ? maxExpectedSize : tempSize * 2) }
                            let speed = tempSize > lastTempSize ? await MainActor.run { self.formatBytes(Int64(Double(tempSize - lastTempSize) / max(elapsed, 0.1))) } + "/s" : "calculating..."
                            let formattedSize = await MainActor.run { self.formatBytes(tempSize) }
                            
                            print("🟡 [MERGE] \(progressBar) \(formattedSize) @ \(speed)")
                            Task { @MainActor in
                                let percent = maxExpectedSize > 0 ? Int((Double(tempSize) / Double(maxExpectedSize)) * 100) : 0
                                self.addLog("📊 [MERGE] \(progressBar) \(formattedSize) (\(percent)%) @ \(speed)", level: .progress)
                            }
                            
                            lastTempSize = tempSize
                            lastUpdateTime = Date()
                            lastSizeChangeTime = Date()
                            stableCount = 0
                            stuckWarningShown = false // Reset warning if we see progress
                        } else if tempSize > 0 {
                            stableCount += 1
                            let timeSinceLastChange = Date().timeIntervalSince(lastSizeChangeTime)
                            
                            // Warn if stuck for 2 minutes
                            if !stuckWarningShown && timeSinceLastChange > 120 {
                                stuckWarningShown = true
                                let formattedSize = await MainActor.run { self.formatBytes(tempSize) }
                                Task { @MainActor in
                                    self.addLog("⚠️ [MERGE] WARNING: No progress for 2 minutes - FFmpeg may be stuck!", level: .warning)
                                    self.addLog("💡 [MERGE] Temp file size: \(formattedSize) (unchanged)", level: .warning)
                                    self.addLog("💡 [MERGE] This may indicate FFmpeg is frozen. Will continue monitoring...", level: .info)
                                }
                            }
                            
                            // If size hasn't changed for 5 seconds, might be done (but check final file)
                            if stableCount >= 50 && elapsed > 5.0 {
                                let formattedSize = await MainActor.run { self.formatBytes(tempSize) }
                                Task { @MainActor in
                                    self.addLog("⏸️ [MERGE] Temp file size stable at \(formattedSize) for 5s - checking for final file...", level: .info)
                                }
                            }
                        }
                    }
                } else if finalExists {
                    // Temp file disappeared, final file exists - merge likely complete
                    if let attributes = try? fileManager.attributesOfItem(atPath: path),
                       let fileSize = attributes[.size] as? Int64 {
                        if fileSize != lastFinalSize {
                            let formattedSize = await MainActor.run { self.formatBytes(fileSize) }
                            print("🟢 [MERGE] Final file size: \(formattedSize)")
                            Task { @MainActor in
                                self.addLog("✅ [MERGE] Final file detected: \(formattedSize)", level: .success)
                            }
                            lastFinalSize = fileSize
                        }
                        
                        if fileSize > 1000 && fileSize == lastFinalSize {
                            stableCount += 1
                            if stableCount >= 3 {
                                // File exists and size is stable
                                foundFile = true
                                let formattedSize = await MainActor.run { self.formatBytes(fileSize) }
                                print("✅ [MERGE WAIT] Final file exists and stable, size: \(formattedSize)")
                                Task { @MainActor in
                                    self.addLog("✅ [MERGE] Merge complete! Final size: \(formattedSize)", level: .success)
                                }
                                break
                            }
                        }
                    }
                } else {
                    // Neither file exists yet
                    if i % 50 == 0 && i > 0 {
                        Task { @MainActor in
                            self.addLog("⏳ [MERGE] Waiting for merge to start... (\(seconds)s)", level: .info)
                        }
                    }
                }
                
                // Check final file separately
                if finalExists && !tempExists {
                    if let attributes = try? fileManager.attributesOfItem(atPath: path),
                       let fileSize = attributes[.size] as? Int64 {
                        if fileSize != lastFinalSize {
                            let progressBar = await MainActor.run { self.generateProgressBar(current: fileSize, total: maxExpectedSize > 0 ? maxExpectedSize : fileSize) }
                            let formattedSize = await MainActor.run { self.formatBytes(fileSize) }
                            print("🟢 [MERGE] \(progressBar) Final: \(formattedSize)")
                            Task { @MainActor in
                                self.addLog("📊 [MERGE] \(progressBar) Final file: \(formattedSize)", level: .progress)
                            }
                            lastFinalSize = fileSize
                            stableCount = 0
                        } else {
                            stableCount += 1
                            if stableCount >= 3 {
                                foundFile = true
                                let formattedSize = await MainActor.run { self.formatBytes(fileSize) }
                                Task { @MainActor in
                                    self.addLog("✅ [MERGE] Merge complete! File size: \(formattedSize)", level: .success)
                                }
                                break
                            }
                        }
                    }
                }
                
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                
                // Periodic status update
                if i % 100 == 0 && i > 0 {
                    let status = tempExists ? "temp file exists" : (finalExists ? "final file exists" : "waiting for files")
                    Task { @MainActor in
                        self.addLog("⏳ [MERGE] Status: \(status) (\(seconds)s elapsed)", level: .info)
                    }
                }
            }
            
            if !foundFile {
                print("⚠️ [MERGE WAIT] WARNING: Merge timeout reached, proceeding with file check")
                Task { @MainActor in
                    self.addLog("⚠️ [MERGE] Timeout reached (5 minutes), proceeding with file check", level: .warning)
                }
            }
        } else {
            print("🔵 [MERGE WAIT] No merge detected, proceeding with normal file check")
        }
        
        // Wait for final file to exist and be stable
        print("🔵 [FINALIZE] Starting final file check")
        Task { @MainActor in
            self.progress.localizedDescription = NSLocalizedString("Finalizing...", comment: "progress description")
            self.addLog("🔧 Step 1: Finalizing download...", level: .info)
            self.addLog("🔧 Step 2: Checking file existence and stability...", level: .info)
        }
        
        // Wait for file to exist
        var fileExists = false
        for i in 0..<100 { // Wait up to 10 seconds for file to appear
            if fileManager.fileExists(atPath: path) {
                fileExists = true
                print("✅ [FINALIZE] File exists at path: \(path)")
                Task { @MainActor in
                    self.addLog("✅ File found: \((path as NSString).lastPathComponent)", level: .success)
                }
                break
            }
            if i % 10 == 0 && i > 0 {
                print("🟠 [FINALIZE] File not found yet, waiting... (\(i/10) seconds)")
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        if !fileExists {
            print("⚠️ [FINALIZE] WARNING: File does not exist at path: \(path)")
            Task { @MainActor in
                self.addLog("⚠️ Expected file not found, searching alternatives...")
            }
            // Try to find any .mp4 file that matches the pattern
            let baseName = (path as NSString).lastPathComponent.replacingOccurrences(of: ".mp4", with: "")
            print("🔍 [FINALIZE] Searching for files matching: \(baseName)")
            // Use nonisolated helper function for file enumeration
            let foundFile = await findMP4File(matching: baseName, in: downloadsDir)
            if let foundPath = foundFile {
                print("✅ [FINALIZE] Found alternative file: \(foundPath.path)")
                Task { @MainActor in
                    self.addLog("✅ Using alternative file: \(foundPath.lastPathComponent)", level: .success)
                }
                if #available(iOS 16.0, *) {
                    return URL(filePath: foundPath.path)
                } else {
                    return URL(fileURLWithPath: foundPath.path)
                }
            }
            print("❌ [FINALIZE] No alternative file found")
        }
        
        // Now wait for file size to stabilize
        print("🔵 [STABILITY] Checking file size stability")
        var previousSize: Int64 = 0
        var stableCount = 0
        
        for i in 0..<50 { // Check up to 5 seconds
            if let attributes = try? fileManager.attributesOfItem(atPath: path),
               let fileSize = attributes[.size] as? Int64 {
                if fileSize == previousSize && fileSize > 0 {
                    stableCount += 1
                    if i % 5 == 0 {
                        print("🟢 [STABILITY] File size stable check \(stableCount)/3: \(fileSize) bytes")
                    }
                    if stableCount >= 3 { // File size stable for 3 checks (0.3 seconds)
                        print("✅ [STABILITY] File size stable at \(fileSize) bytes (\(String(format: "%.2f", Double(fileSize) / 1_000_000)) MB) after \(i) checks")
                        Task { @MainActor in
                            self.addLog("✅ File ready: \(String(format: "%.2f", Double(fileSize) / 1_000_000)) MB", level: .success)
                        }
                        break
                    }
                } else {
                    if fileSize != previousSize {
                        print("🟡 [STABILITY] File size changed: \(previousSize) → \(fileSize) bytes (reset stability count)")
                        stableCount = 0
                    }
                }
                previousSize = fileSize
            } else {
                if i % 10 == 0 {
                    print("🟠 [STABILITY] Cannot read file attributes (check \(i))")
                }
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        print("✅ [COMPLETE] File check complete, returning URL")
        Task { @MainActor in
            self.progress.localizedDescription = nil
            self.mergeInProgress = false
            self.addLog("✅ Step 3: File verified and ready!", level: .success)
            self.addLog("✅ Download complete! File: \(fileURL.lastPathComponent)", level: .success)
        }
        
        // Clean up any temp files from yt-dlp immediately after download completes
        self.cleanupTempFiles(in: downloadsDir)
        
        // Check if thumbnail embedding succeeded, use fallback if needed
        // Note: yt-dlp always downloads the thumbnail file (--write-thumbnail), but doesn't always embed it
        // So we can reliably use the downloaded thumbnail file for ffmpeg fallback
        Task { @MainActor in
            self.addLog("🔍 Step 1: Checking if thumbnail was embedded by yt-dlp...", level: .info)
        }
        let hasThumbnail = await checkIfThumbnailEmbedded(fileURL: fileURL)
        
        if !hasThumbnail {
            Task { @MainActor in
                self.addLog("⚠️ Step 2: Thumbnail not embedded by yt-dlp (common - yt-dlp downloads but doesn't always embed)", level: .warning)
                self.addLog("ℹ️ yt-dlp always downloads the thumbnail file, so we can use it for embedding", level: .info)
                self.addLog("🔄 Step 3: Using ffmpeg to embed the downloaded thumbnail...", level: .info)
                self.addLog("⏱️ Thumbnail embedding timeout: 20 seconds (will skip if exceeded)", level: .info)
            }
            
            // Try embedding with 20 second timeout
            let embeddingStartTime = Date()
            let embeddingSucceeded: Bool
            do {
                embeddingSucceeded = try await withTimeout(seconds: 20.0) { [self] in
                    return await self.tryEmbedThumbnailIfNeeded(for: fileURL, in: downloadsDir)
                }
            } catch is TimeoutError {
                // Timeout occurred - delete thumbnail file and skip embedding
                let elapsed = Date().timeIntervalSince(embeddingStartTime)
                Task { @MainActor in
                    self.addLog("⏱️ Thumbnail embedding exceeded 20 seconds (took \(Int(elapsed))s) - skipping", level: .warning)
                    self.addLog("🗑️ Deleting thumbnail file and keeping audio file only", level: .info)
                    self.addLog("💡 Better than nothing - you still have the full audio file!", level: .info)
                }
                
                // Delete thumbnail file
                let fileName = fileURL.deletingPathExtension().lastPathComponent
                let possibleThumbnailNames = [
                    "\(fileName).jpg",
                    "\(fileName).jpeg",
                    "\(fileName).png",
                    "\(fileName).webp",
                    "\(fileName).thumb.jpg",
                    "\(fileName).thumbnail.jpg"
                ]
                
                let fileManager = FileManager.default
                for thumbName in possibleThumbnailNames {
                    let thumbPath = downloadsDir.appendingPathComponent(thumbName)
                    if fileManager.fileExists(atPath: thumbPath.path) {
                        try? fileManager.removeItem(at: thumbPath)
                        Task { @MainActor in
                            self.addLog("🗑️ Deleted thumbnail file: \(thumbName)", level: .debug)
                        }
                    }
                }
                
                // Also search for any thumbnail files
                if let thumbnailURL = await findThumbnailFile(matching: fileName, in: downloadsDir) {
                    try? fileManager.removeItem(at: thumbnailURL)
                    Task { @MainActor in
                        self.addLog("🗑️ Deleted thumbnail file: \(thumbnailURL.lastPathComponent)", level: .debug)
                    }
                }
                
                embeddingSucceeded = false
            }
            
            if !embeddingSucceeded {
                Task { @MainActor in
                    self.addLog("❌ All thumbnail embedding attempts failed", level: .error)
                    self.addLog("🗑️ Thumbnail file has been deleted - keeping audio file only", level: .info)
                    self.addLog("💡 Better than nothing - you still have the full audio file!", level: .info)
                    self.addLog("⚠️ Thumbnail embedding process finished - failed", level: .warning)
                }
            } else {
                Task { @MainActor in
                    self.addLog("✅ Thumbnail embedding process finished - succeeded via ffmpeg", level: .success)
                }
            }
        } else {
            Task { @MainActor in
                self.addLog("✅ Step 2: Thumbnail successfully embedded by yt-dlp", level: .success)
                self.addLog("🧹 Cleaning up any leftover thumbnail files...", level: .debug)
            }
            // Clean up any thumbnail files that were saved but not needed
            await cleanupThumbnailFiles(for: fileURL, in: downloadsDir)
            Task { @MainActor in
                self.addLog("✅ Thumbnail embedding process finished - already embedded by yt-dlp", level: .success)
            }
        }
        
        // Final cleanup
        self.cleanupTempFiles(in: downloadsDir)
        
        Task { @MainActor in
            self.addLog("✅ All processing complete! File ready: \(fileURL.lastPathComponent)", level: .success)
        }
        
        return fileURL
    }
    
    // MARK: - File System Helpers (nonisolated for async safety)
    
    /// Find all MP4 files in a directory (nonisolated helper)
    /// - Parameter directory: The directory to search in
    /// - Returns: Array of tuples containing (file URL, modification date) for all MP4 files found
    nonisolated func findMP4Files(in directory: URL) async -> [(URL, Date)] {
        await withCheckedContinuation { continuation in
            Task.detached {
                var results: [(URL, Date)] = []
                let fileManager = FileManager.default
                let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
                while let element = enumerator?.nextObject() as? URL {
                    if element.pathExtension == "mp4" && !element.lastPathComponent.contains(".temp") && !element.lastPathComponent.contains(".f") {
                        if let modDate = try? element.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                            results.append((element, modDate))
                        }
                    }
                }
                continuation.resume(returning: results)
            }
        }
    }
    
    /// Find an MP4 file matching a base name (nonisolated helper)
    /// - Parameters:
    ///   - baseName: The base name to match (partial filename)
    ///   - directory: The directory to search in
    /// - Returns: The first matching MP4 file URL, or nil if not found
    nonisolated func findMP4File(matching baseName: String, in directory: URL) async -> URL? {
        await withCheckedContinuation { continuation in
            Task.detached {
                var result: URL? = nil
                let fileManager = FileManager.default
                let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
                while let url = enumerator?.nextObject() as? URL {
                    if url.pathExtension == "mp4" && url.lastPathComponent.contains(baseName) && !url.lastPathComponent.contains(".temp") {
                        result = url
                        break
                    }
                }
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Find a thumbnail file matching a filename (nonisolated helper)
    /// - Parameters:
    ///   - fileName: The base filename to match against
    ///   - directory: The directory to search in
    /// - Returns: The first matching thumbnail file URL (jpg, jpeg, png, webp), or nil if not found
    nonisolated func findThumbnailFile(matching fileName: String, in directory: URL) async -> URL? {
        await withCheckedContinuation { continuation in
            Task.detached {
                var result: URL? = nil
                let fileManager = FileManager.default
                let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.contentTypeKey], options: [.skipsHiddenFiles])
                while let url = enumerator?.nextObject() as? URL {
                    let ext = url.pathExtension.lowercased()
                    if ["jpg", "jpeg", "png", "webp"].contains(ext) {
                        // Check if filename is similar to the audio file
                        let thumbBase = url.deletingPathExtension().lastPathComponent
                        if thumbBase.contains(fileName) || fileName.contains(thumbBase) {
                            result = url
                            break
                        }
                    }
                }
                continuation.resume(returning: result)
            }
        }
    }
    
    // MARK: - Thumbnail Embedding
    
    /// Check if audio file already has embedded thumbnail
    /// - Parameter fileURL: The audio file to check
    /// - Returns: True if thumbnail is embedded, false otherwise
    private func checkIfThumbnailEmbedded(fileURL: URL) async -> Bool {
        await Task.detached { () -> Bool in
            let asset = AVURLAsset(url: fileURL)
            let metadata = try? await asset.load(.metadata)
            return metadata?.contains { item in
                item.commonKey == .commonKeyArtwork
            } ?? false
        }.value
    }
    
    /// Clean up thumbnail files that were saved but not needed (when embedding succeeded)
    /// - Parameters:
    ///   - fileURL: The audio file
    ///   - directory: The directory to search for thumbnail files
    private func cleanupThumbnailFiles(for fileURL: URL, in directory: URL) async {
        let fileManager = FileManager.default
        let fileName = fileURL.deletingPathExtension().lastPathComponent
        
        let possibleThumbnailNames = [
            "\(fileName).jpg",
            "\(fileName).jpeg",
            "\(fileName).png",
            "\(fileName).webp",
            "\(fileName).thumb.jpg",
            "\(fileName).thumbnail.jpg"
        ]
        
        for thumbName in possibleThumbnailNames {
            let thumbPath = directory.appendingPathComponent(thumbName)
            if fileManager.fileExists(atPath: thumbPath.path) {
                try? fileManager.removeItem(at: thumbPath)
                Task { @MainActor in
                    self.addLog("🧹 Removed thumbnail file: \(thumbName)", level: .debug)
                }
            }
        }
    }
    
    /// Attempts to embed thumbnail/cover art into audio files using ffmpeg
    /// 
    /// This is a fallback method used when yt-dlp's built-in thumbnail embedding fails
    /// or is disabled (to avoid freezing issues). The function:
    /// 
    /// 1. Checks if file already has embedded thumbnail (skips if present)
    /// 2. Searches for thumbnail files saved by yt-dlp (--write-thumbnail)
    /// 3. Uses ffmpeg to embed thumbnail as attached picture
    /// 4. Handles different audio formats (MP3, M4A, AAC, FLAC) with format-specific options
    /// 5. Includes dynamic timeout protection based on file size:
    ///    - Files < 25 MB: 5 seconds timeout
    ///    - Files >= 25 MB: 60 seconds timeout
    /// 6. Deletes thumbnail file if embedding fails
    /// 
    /// Supported formats: M4A, MP3, AAC, FLAC
    /// Unsupported formats: Opus, OGG (don't reliably support embedded artwork)
    /// 
    /// - Parameters:
    ///   - fileURL: The audio file to embed thumbnail into
    ///   - directory: The directory to search for thumbnail files
    /// - Returns: True if thumbnail was successfully embedded, false otherwise
    func tryEmbedThumbnailIfNeeded(for fileURL: URL, in directory: URL) async -> Bool {
        let fileManager = FileManager.default
        let fileName = fileURL.deletingPathExtension().lastPathComponent
        let fileExt = fileURL.pathExtension.lowercased()
        
        // Only try for audio files that support embedded thumbnails
        // Note: Opus format doesn't support embedded thumbnails via ffmpeg
        // Skip opus and ogg as they don't reliably support embedded artwork
        guard ["m4a", "mp3", "aac", "flac"].contains(fileExt) else {
            if ["opus", "ogg"].contains(fileExt) {
                Task { @MainActor in
                    self.addLog("ℹ️ Opus/OGG format doesn't support embedded thumbnails, skipping", level: .info)
                    self.addLog("⚠️ Thumbnail embedding finished - format not supported", level: .warning)
                }
            } else {
                Task { @MainActor in
                    self.addLog("⚠️ Thumbnail embedding finished - format not supported", level: .warning)
                }
            }
            return false
        }
        
        // Check if file already has embedded thumbnail by checking for attached picture
        // Do this check asynchronously to avoid blocking
        Task { @MainActor in
            self.addLog("🔍 Checking if file already has embedded thumbnail...", level: .info)
        }
        let hasThumbnail = await Task.detached { () -> Bool in
            let asset = AVURLAsset(url: fileURL)
            let metadata = try? await asset.load(.metadata)
            return metadata?.contains { item in
                item.commonKey == .commonKeyArtwork
            } ?? false
        }.value
        
        if hasThumbnail {
            Task { @MainActor in
                self.addLog("✅ Thumbnail already embedded in file, skipping", level: .success)
            }
            return true
        }
        
        Task { @MainActor in
            self.addLog("ℹ️ No embedded thumbnail found, proceeding with embedding...", level: .info)
        }
        
        // Look for thumbnail files (yt-dlp always downloads them with --write-thumbnail)
        // Since yt-dlp always gets the art, the file should be available
        Task { @MainActor in
            self.addLog("🔍 Searching for thumbnail file (yt-dlp should have downloaded it)...", level: .info)
        }
        let possibleThumbnailNames = [
            "\(fileName).jpg",
            "\(fileName).jpeg",
            "\(fileName).png",
            "\(fileName).webp",
            // Also check for generic thumbnail names
            "\(fileName).thumb.jpg",
            "\(fileName).thumbnail.jpg"
        ]
        
        var thumbnailURL: URL?
        for thumbName in possibleThumbnailNames {
            let thumbPath = directory.appendingPathComponent(thumbName)
            if fileManager.fileExists(atPath: thumbPath.path) {
                thumbnailURL = thumbPath
                Task { @MainActor in
                    self.addLog("✅ Found thumbnail file: \(thumbName)", level: .success)
                }
                break
            }
        }
        
        // Also search for any .jpg/.png/.webp files that might be the thumbnail
        if thumbnailURL == nil {
            Task { @MainActor in
                self.addLog("🔍 Searching for thumbnail with similar filename...", level: .info)
            }
            // Use nonisolated helper function for file enumeration
            thumbnailURL = await findThumbnailFile(matching: fileName, in: directory)
            if thumbnailURL != nil {
                Task { @MainActor in
                    self.addLog("✅ Found thumbnail file: \(thumbnailURL!.lastPathComponent)", level: .success)
                }
            }
        }
        
        guard let thumbnailURL = thumbnailURL else {
            Task { @MainActor in
                self.addLog("❌ No thumbnail file found to embed (unexpected - yt-dlp should have downloaded it)", level: .error)
                self.addLog("ℹ️ Thumbnail embedding skipped - file will not have cover art", level: .warning)
                self.addLog("⚠️ Thumbnail embedding finished - no thumbnail file found", level: .warning)
            }
            return false
        }
        
        Task { @MainActor in
            self.addLog("🖼️ Step 1: Found thumbnail file downloaded by yt-dlp: \(thumbnailURL.lastPathComponent)", level: .success)
            self.addLog("🖼️ Step 2: Preparing to embed thumbnail using ffmpeg...", level: .info)
            self.addLog("📁 Input file: \(fileURL.lastPathComponent)", level: .debug)
        }
        
        // Use ffmpeg to embed thumbnail as attached picture
        let tempOutput = fileURL.deletingPathExtension().appendingPathExtension("temp.\(fileExt)")
        
        // Remove temp file if it exists
        try? fileManager.removeItem(at: tempOutput)
        
        // Get file size to determine appropriate timeout
        let fileSize: Int64
        if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
           let size = attributes[.size] as? Int64 {
            fileSize = size
        } else {
            fileSize = 0
        }
        
        // Calculate timeout based on file size
        // Files < 25 MB: 5 seconds, Files >= 25 MB: 60 seconds
        let timeoutSeconds: TimeInterval
        let fileSizeMB = Double(fileSize) / (1024 * 1024)
        if fileSize < 25 * 1024 * 1024 { // Less than 25 MB
            timeoutSeconds = 5.0
        } else {
            timeoutSeconds = 60.0
        }
        
        Task { @MainActor in
            self.addLog("🖼️ Step 3: Starting ffmpeg embedding process...", level: .info)
            if fileSize > 0 {
                self.addLog("📊 File size: \(String(format: "%.2f", fileSizeMB)) MB", level: .info)
            }
            self.addLog("⏱️ FFmpeg timeout: \(Int(timeoutSeconds)) seconds (based on file size)", level: .info)
        }
        
        // Run ffmpeg with dynamic timeout to prevent hanging
        do {
            let result = try await withTimeout(seconds: timeoutSeconds) {
                await Task.detached {
                    // Build ffmpeg command to embed thumbnail
                    // For audio files, we need to add the thumbnail as a video stream with disposition:attached_pic
                    // Use format-specific options
                    let ffmpegResult: Int32
                    if fileExt == "mp3" {
                        // MP3 needs ID3v2 version specified
                        ffmpegResult = Int32(ffmpeg("FFmpeg-iOS",
                                           "-y",  // Overwrite output
                                           "-i", fileURL.path,  // Input audio
                                           "-i", thumbnailURL.path,  // Input thumbnail
                                           "-map", "0:a",  // Map audio stream
                                           "-map", "1",  // Map thumbnail
                                           "-c:a", "copy",  // Copy audio codec
                                           "-c:v", "mjpeg",  // Thumbnail codec
                                           "-disposition:v:0", "attached_pic",  // Set as attached picture
                                           "-id3v2_version", "3",  // For mp3 compatibility
                                           tempOutput.path))
                    } else if fileExt == "m4a" {
                        // M4A needs explicit mp4 format
                        ffmpegResult = Int32(ffmpeg("FFmpeg-iOS",
                                           "-y",  // Overwrite output
                                           "-i", fileURL.path,  // Input audio
                                           "-i", thumbnailURL.path,  // Input thumbnail
                                           "-map", "0:a",  // Map audio stream
                                           "-map", "1",  // Map thumbnail
                                           "-c:a", "copy",  // Copy audio codec
                                           "-c:v", "mjpeg",  // Thumbnail codec
                                           "-disposition:v:0", "attached_pic",  // Set as attached picture
                                           "-f", "mp4",  // Explicit mp4 format for m4a
                                           tempOutput.path))
                    } else {
                        // For other formats (aac, flac)
                        ffmpegResult = Int32(ffmpeg("FFmpeg-iOS",
                                           "-y",  // Overwrite output
                                           "-i", fileURL.path,  // Input audio
                                           "-i", thumbnailURL.path,  // Input thumbnail
                                           "-map", "0:a",  // Map audio stream
                                           "-map", "1",  // Map thumbnail
                                           "-c:a", "copy",  // Copy audio codec
                                           "-c:v", "mjpeg",  // Thumbnail codec
                                           "-disposition:v:0", "attached_pic",  // Set as attached picture
                                           tempOutput.path))
                    }
                    return ffmpegResult
                }.value
            }
            
            var success = false
            await MainActor.run {
                if result == 0 && fileManager.fileExists(atPath: tempOutput.path) {
                    // Replace original with new file
                    do {
                        self.addLog("✅ Step 4: FFmpeg completed successfully", level: .success)
                        self.addLog("🔄 Step 5: Replacing original file with thumbnail-embedded version...", level: .info)
                        try fileManager.removeItem(at: fileURL)
                        try fileManager.moveItem(at: tempOutput, to: fileURL)
                        self.addLog("✅ Step 6: Thumbnail embedded successfully!", level: .success)
                        // Clean up thumbnail file
                        try? fileManager.removeItem(at: thumbnailURL)
                        self.addLog("🧹 Step 7: Cleaned up temporary thumbnail file", level: .debug)
                        self.addLog("✅ Thumbnail embedding complete!", level: .success)
                        success = true
                    } catch {
                        self.addLog("❌ Step 5 failed: \(error.localizedDescription)", level: .error)
                        self.addLog("⚠️ Original file preserved, thumbnail embedding failed", level: .warning)
                        // Clean up temp file
                        try? fileManager.removeItem(at: tempOutput)
                        // Delete thumbnail file since embedding failed
                        try? fileManager.removeItem(at: thumbnailURL)
                        self.addLog("🗑️ Deleted thumbnail file (embedding failed)", level: .info)
                        self.addLog("❌ Thumbnail embedding finished - failed", level: .error)
                    }
                } else {
                    self.addLog("❌ Step 4 failed: FFmpeg exit code \(result)", level: .error)
                    self.addLog("⚠️ Thumbnail embedding failed - file will not have cover art", level: .warning)
                    // Clean up temp file
                    try? fileManager.removeItem(at: tempOutput)
                    // Delete thumbnail file since embedding failed
                    try? fileManager.removeItem(at: thumbnailURL)
                    self.addLog("🗑️ Deleted thumbnail file (embedding failed)", level: .info)
                    self.addLog("❌ Thumbnail embedding finished - failed", level: .error)
                }
            }
            return success
        } catch {
            // Timeout or other error occurred
            await MainActor.run {
                self.addLog("❌ Thumbnail embedding timed out or failed: \(error.localizedDescription)", level: .error)
                self.addLog("⚠️ FFmpeg timeout reached (\(Int(timeoutSeconds)) seconds) - skipping to prevent freezing", level: .warning)
                self.addLog("ℹ️ File will not have embedded cover art", level: .info)
            }
            // Clean up temp file
            try? fileManager.removeItem(at: tempOutput)
            // Delete thumbnail file since embedding failed
            try? fileManager.removeItem(at: thumbnailURL)
            Task { @MainActor in
                self.addLog("🗑️ Deleted thumbnail file (embedding failed)", level: .info)
                self.addLog("❌ Thumbnail embedding finished - failed (timeout)", level: .error)
            }
            return false
        }
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
        // Always save to Files folder only (no Photos export)
        // File is already in Documents directory
        Task { @MainActor in
            self.addLog("✅ File saved to Downloads folder", level: .success)
            
            // Small delay to ensure file is fully written
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Open the folder (Documents directory) in Files app
            if let documentsURL = try? self.documentsDirectory() {
                self.openFolder(url: documentsURL)
            }
        }
    }
    
    func openFolder(url: URL) {
        // Open the Documents folder in Files app
        // Use the file:// URL scheme to open in Files app
        DispatchQueue.main.async {
            // Create a URL that points to the Documents directory
            // The Files app can open file:// URLs
            let folderURL = url
            if UIApplication.shared.canOpenURL(folderURL) {
                UIApplication.shared.open(folderURL) { success in
                    if !success {
                        print(#function, "Failed to open folder:", folderURL)
                        Task { @MainActor in
                            self.addLog("💡 File saved. Open Files app to view downloads.", level: .info)
                        }
                    }
                }
            } else {
                Task { @MainActor in
                    self.addLog("💡 File saved. Open Files app to view downloads.", level: .info)
                }
            }
        }
    }
    
    func notify(body: String) {
        let content = UNMutableNotificationContent()
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print(#function, "Failed to send notification:", error)
            }
        }
    }
    
    // MARK: - Cleanup temp files
    
    // MARK: - Progress Bar Helpers
    
    /// Generate a CLI-style progress bar string for visual progress indication
    /// - Parameters:
    ///   - current: Current progress value (bytes or units)
    ///   - total: Total expected value
    ///   - width: Width of the progress bar in characters (default: 40)
    /// - Returns: Formatted progress bar string like "[████████░░░░░░░░] 50%"
    nonisolated func generateProgressBar(current: Int64, total: Int64, width: Int = 40) -> String {
        guard total > 0 else {
            return String(repeating: "░", count: width)
        }
        
        let percent = min(100, max(0, Int((Double(current) / Double(total)) * 100)))
        let filled = Int((Double(percent) / 100.0) * Double(width))
        let empty = width - filled
        
        let filledBar = String(repeating: "█", count: filled)
        let emptyBar = String(repeating: "░", count: empty)
        
        return "[\(filledBar)\(emptyBar)] \(percent)%"
    }
    
    /// Format bytes to human-readable string (e.g., "15.2 MB", "1.5 KB")
    /// - Parameter bytes: The number of bytes to format
    /// - Returns: Formatted string with appropriate unit (MB, KB, or Bytes)
    nonisolated func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useBytes]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // MARK: - File Cleanup
    
    /// Cleans up temporary files that might be left behind from failed or interrupted downloads
    /// 
    /// Removes:
    /// - `.temp.*` files (from merging/embedding operations)
    /// - `.frag` files (fragment files)
    /// - `.f123`, `.f456`, etc. (yt-dlp fragment files - format: .f followed by numbers)
    /// - `.part` files (partial downloads)
    /// 
    /// This helps prevent disk space issues and keeps the downloads folder clean.
    /// 
    /// - Parameter directory: The directory to clean up (typically Documents/downloads folder)
    func cleanupTempFiles(in directory: URL) {
        let fileManager = FileManager.default
        // Use enumerator to recursively find all temp files
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return
        }
        
        var cleanedCount = 0
        while let fileURL = enumerator.nextObject() as? URL {
            let fileName = fileURL.lastPathComponent
            let filePath = fileURL.path
            
            // Clean up temp files:
            // - .temp.mp4, .temp.m4a, etc. (from merging/embedding)
            // - .frag files (fragments)
            // - .f123, .f456, etc. (yt-dlp fragment files - format: .f followed by numbers)
            // - Files ending in .part (partial downloads)
            // - Files with .ytdl extension (yt-dlp temp files)
            // - Files matching pattern like filename.temp.ext
            let shouldClean = fileName.contains(".temp.") || 
                              fileName.hasSuffix(".frag") ||
                              fileName.hasSuffix(".part") ||
                              fileName.hasSuffix(".ytdl") ||
                              (fileName.hasPrefix(".f") && fileName.count <= 10 && fileName.dropFirst().allSatisfy(\.isNumber)) ||
                              filePath.contains(".temp")
            
            if shouldClean {
                do {
                    try fileManager.removeItem(at: fileURL)
                    cleanedCount += 1
                    print("🧹 Cleaned up temp file: \(fileName)")
                } catch {
                    print("⚠️ Failed to remove temp file \(fileName): \(error)")
                    Task { @MainActor in
                        self.addLog("⚠️ Failed to remove temp file \(fileName): \(error.localizedDescription)", level: .warning)
                    }
                }
            }
        }
        
        if cleanedCount > 0 {
            Task { @MainActor in
                self.addLog("🧹 Cleaned up \(cleanedCount) temp file(s)", level: .debug)
            }
        }
    }
}

// MARK: - Timeout helper

/// Run an async operation with a timeout
private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        // Add the actual operation
        group.addTask {
            try await operation()
        }
        
        // Add timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        
        // Return the first result (either operation or timeout)
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

private struct TimeoutError: Error {
    var localizedDescription: String {
        "Operation timed out"
    }
}

// MARK: - ANSI helpers

// Regex for use in async contexts (NSRegularExpression is Sendable)
private let ansiEscapeRegex: NSRegularExpression = {
    // Matches CSI-style ANSI escape sequences that yt-dlp emits when color is enabled
    let pattern = "\u{001B}\\[[0-9;?]*[ -/]*[@-~]"
    return try! NSRegularExpression(pattern: pattern, options: [])
}()

// MARK: - String Extensions for ANSI/Control Character Removal

/// Extension to String for cleaning up terminal output from yt-dlp
extension String {
    func removingANSIEscapeSequences() -> String {
        let range = NSRange(startIndex..<endIndex, in: self)
        return ansiEscapeRegex.stringByReplacingMatches(
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
