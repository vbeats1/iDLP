//
//  MainView.swift
//
//  Based on original by Changbeom Ahn
//

import Foundation
import SwiftUI
import YoutubeDL
import FFmpegSupport
import AVFoundation
import WebKit

// Global alias so AppModel’s TimeRange compiles
typealias TimeRange = Range<TimeInterval>

@available(iOS 13.0.0, *)
struct MainView: View {
    @State var alertMessage: String?
    @State var isShowingAlert = false
    
    @State var error: Error? {
        didSet {
            guard error != nil else { return }
            alertMessage = error?.localizedDescription
            isShowingAlert = true
        }
    }
    
    @EnvironmentObject var app: AppModel
    
    @State var urlString = ""
    @State var isExpanded = false
    
    @AppStorage("isIdleTimerDisabled") var isIdleTimerDisabled =
        UIApplication.shared.isIdleTimerDisabled
    
    @State private var showBrowser = false
    
    enum FormatFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case video = "Video only"
        case audio = "Audio only"
        
        var id: String { rawValue }
    }
    
    @State private var formatFilter: FormatFilter = .all
    
    var filteredFormats: [AppModel.FormatChoice] {
        switch formatFilter {
        case .all:
            return app.formatChoices
        case .video:
            return app.formatChoices.filter { $0.isVideoOnly || $0.isMuxed }
        case .audio:
            return app.formatChoices.filter { $0.isAudioOnly }
        }
    }
    
    var body: some View {
        List {
            // General settings
            Section {
                Toggle("Keep screen turned on", isOn: $isIdleTimerDisabled)
            }
            
            // URL input + helpers + fetch button
            Section(header: Text("URL")) {
                DisclosureGroup(isExpanded: $isExpanded) {
                    Button("Paste URL") {
                        let pasteBoard = UIPasteboard.general
                        guard let url = pasteBoard.url
                                ?? pasteBoard.string.flatMap({ URL(string: $0) }) else {
                            alert(message: "Nothing to paste")
                            return
                        }
                        urlString = url.absoluteString
                        app.url = url
                    }
                    Button(#"Prepend "y" to URL in Safari"#) {
                        open(url: URL(string: "https://youtube.com")!)
                    }
                    Button("Download shortcut") {
                        open(url: URL(string: "https://www.icloud.com/shortcuts/e226114f6e6c4440b9c466d1ebe8fbfc")!)
                    }
                } label: {
                    if #available(iOS 15.0, *) {
                        TextField("Enter URL", text: $urlString)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .keyboardType(.URL)
                            .onSubmit {
                                guard let url = URL(string: urlString) else {
                                    alert(message: "Invalid URL")
                                    return
                                }
                                app.url = url
                            }
                    } else {
                        TextField("Enter URL", text: $urlString)
                    }
                }
                
                Button("Fetch formats") {
                    guard let url = app.url ?? URL(string: urlString) else {
                        alert(message: "No valid URL")
                        return
                    }
                    app.url = url
                    Task {
                        await app.fetchFormats(for: url)
                    }
                }
            }
            
            // Format picker section (populated from yt-dlp -F)
            if !app.formatChoices.isEmpty {
                Section(header: Text("Formats (\(filteredFormats.count))")) {
                    // Debug line so you can confirm something was parsed
                    Text("Parsed formats: \(app.formatChoices.count)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    
                    Picker("Filter", selection: $formatFilter) {
                        ForEach(FormatFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    
                    // Scrollable clickable list of formats
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredFormats) { choice in
                                FormatRow(
                                    choice: choice,
                                    isSelected: app.selectedFormatID == choice.id
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    app.selectedFormatID = choice.id
                                    print("UI: selected formatID=\(choice.id)")
                                }
                                Divider()
                            }
                        }
                    }
                    .frame(minHeight: 220, maxHeight: 380)
                }
                
                Section {
                    Button("Start Download") {
                        guard let url = app.url ?? URL(string: urlString) else {
                            alert(message: "No valid URL")
                            return
                        }
                        Task {
                            await app.startDownload(url: url)
                        }
                    }
                    .disabled(app.url == nil && URL(string: urlString) == nil)
                }
            }
            
            if app.showProgress {
                Section {
                    ProgressView(app.progress)
                }
            }
            
            app.youtubeDL.version.map { ver in
                Section {
                    Text("yt-dlp version \(ver)")
                }
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = isIdleTimerDisabled
        }
        .onChange(of: app.url) { newValue in
            guard let url = newValue else { return }
            urlString = url.absoluteString
            if isExpanded {
                isExpanded = false
            }
        }
        .onChange(of: isIdleTimerDisabled) { newValue in
            UIApplication.shared.isIdleTimerDisabled = newValue
        }
        .onReceive(app.$error) {
            error = $0
        }
        .alert(isPresented: $isShowingAlert) {
            Alert(title: Text(alertMessage ?? "no message?"))
        }
        // Use sheet(isPresented:) to avoid needing URL : Identifiable
        .sheet(isPresented: Binding(
            get: { app.webViewURL != nil },
            set: { if !$0 { app.webViewURL = nil } }
        )) {
            if let url = app.webViewURL {
                WebView(url: url) { url in
                    app.webViewURL = nil
                    Task {
                        await app.startDownload(url: url)
                    }
                }
            }
        }
        .sheet(isPresented: $showBrowser) {
            Browser()
        }
        .toolbar {
            Button {
                showBrowser = true
            } label: {
                Image(systemName: "safari")
            }
        }
    }
    
    // MARK: - Helpers
    
    func open(url: URL) {
        UIApplication.shared.open(url, options: [:]) {
            if !$0 {
                alert(message: "Failed to open \(url)")
            }
        }
    }
    
    func alert(message: String) {
        alertMessage = message
        isShowingAlert = true
    }
}

// MARK: - Clickable format row

struct FormatRow: View {
    let choice: AppModel.FormatChoice
    let isSelected: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(choice.id)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                
                Text(choice.description)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .imageScale(.medium)
            }
        }
        .padding(6)
        .background(
            isSelected
            ? Color.accentColor.opacity(0.15)
            : Color.clear
        )
    }
}

// MARK: - Helper Types & Extra Views

struct ID<Value>: Identifiable {
    let value: Value
    let id = UUID()
}

// MARK: - TrimView

struct TrimView: View {
    class Model: NSObject, ObservableObject {
        let url: URL
        init(url: URL) {
            self.url = url
        }
    }
    
    @StateObject var model: Model
    @EnvironmentObject var app: AppModel
    
    @State var time = Date(timeIntervalSince1970: 0)
    
    let timeFormatter: Formatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
    
    @State var start = ""
    @State var length = ""
    @State var end = ""
    
    enum FocusedField: Hashable {
        case start, length, end
    }
    
    @FocusState var focus: FocusedField?
    
    var body: some View {
        VStack {
            TextField("Start", text: $start)
                .focused($focus, equals: .start)
            TextField("Length", text: $length)
                .focused($focus, equals: .length)
            TextField("End", text: $end)
                .focused($focus, equals: .end)
            Button {
                Task {
                    await transcode()
                }
            } label: {
                Text("Transcode")
            }
        }
        .onChange(of: start) { newValue in
            updateLength(start: newValue, end: end)
        }
        .onChange(of: end) { newValue in
            guard focus == .end else { return }
            updateLength(start: start, end: newValue)
        }
        .onChange(of: length) { newValue in
            guard focus == .length else { return }
            updateEnd(start: start, length: newValue)
        }
    }
    
    init(url: URL) {
        _model = StateObject(wrappedValue: Model(url: url))
    }
    
    func transcode() async {
        let s = seconds(start) ?? 0
        let e = seconds(end) ?? 0
        guard s < e else {
            print(#function, "invalid interval:", start, "~", end)
            return
        }
        let out = model.url.deletingPathExtension().appendingPathExtension("mp4")
        try? FileManager.default.removeItem(at: out)
        let pipe = Pipe()
        Task {
            for try await line in pipe.fileHandleForReading.bytes.lines {
                print(#function, line)
            }
        }
        let t0 = Date()
        let ret = ffmpeg("FFmpeg-iOS",
                         "-progress", "pipe:\(pipe.fileHandleForWriting.fileDescriptor)",
                         "-nostats",
                         "-ss", start,
                         "-t", length,
                         "-i", model.url.path,
                         out.path)
        print(#function, ret, "took", Date().timeIntervalSince(t0), "seconds")
        
        let audio = URL(fileURLWithPath: out.path.replacingOccurrences(of: "-otherVideo.mp4", with: "-audioOnly.m4a"))
        let final = URL(fileURLWithPath: out.path.replacingOccurrences(of: "-otherVideo", with: ""))
        let timeRange = CMTimeRange(
            start: CMTime(seconds: Double(s), preferredTimescale: 1),
            end: CMTime(seconds: Double(e), preferredTimescale: 1)
        )
        mux(videoURL: out, audioURL: audio, outputURL: final, timeRange: timeRange)
    }
    
    func mux(videoURL: URL, audioURL: URL, outputURL: URL, timeRange: CMTimeRange) {
        let t0 = ProcessInfo.processInfo.systemUptime
        
        let videoAsset = AVAsset(url: videoURL)
        let audioAsset = AVAsset(url: audioURL)
        
        guard let videoAssetTrack = videoAsset.tracks(withMediaType: .video).first,
              let audioAssetTrack = audioAsset.tracks(withMediaType: .audio).first else {
            print(#function,
                  videoAsset.tracks(withMediaType: .video),
                  audioAsset.tracks(withMediaType: .audio))
            return
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
            try audioCompositionTrack?.insertTimeRange(timeRange, of: audioAssetTrack, at: .zero)
            print(#function, videoAssetTrack.timeRange, audioAssetTrack.timeRange)
        }
        catch {
            print(#function, error)
            return
        }
        
        guard let session = AVAssetExportSession(asset: composition,
                                                 presetName: AVAssetExportPresetPassthrough) else {
            print(#function, "unable to init export session")
            return
        }
        
        session.outputURL = outputURL
        session.outputFileType = .mp4
        print(#function, "merging...")
        
        session.exportAsynchronously {
            print(#function, "finished merge", session.status.rawValue)
            print(#function, "took", ProcessInfo.processInfo.systemUptime - t0)
            if session.status == .completed {
                print(#function, "success")
            } else {
                print(#function, session.error ?? "no error?")
            }
        }
    }
    
    func updateLength(start: String, end: String) {
        guard let s = seconds(start), let e = seconds(end) else {
            return
        }
        let l = e - s
        length = format(l) ?? length
    }
    
    func updateEnd(start: String, length: String) {
        guard let s = seconds(start), let l = seconds(length) else {
            return
        }
        let e = s + l
        end = format(e) ?? end
    }
}

// MARK: - Time helpers

func seconds(_ string: String) -> Int? {
    let components = string.split(separator: ":")
    guard components.count <= 3 else {
        print(#function, "too many components:", string)
        return nil
    }
    
    var seconds = 0
    for component in components {
        guard let number = Int(component) else {
            print(#function, "invalid number:", component)
            return nil
        }
        seconds = 60 * seconds + number
    }
    return seconds
}

func format(_ seconds: Int) -> String? {
    guard seconds >= 0 else { return nil }
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    } else {
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - WebView wrapper

let handlerName = "YoutubeDL"

struct WebView: UIViewRepresentable {
    let url: URL?
    let handler: ((URL) -> Void)?
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.configuration.userContentController.add(context.coordinator, name: handlerName)
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        if let url, webView.url != url {
            print(#function, url)
            webView.load(URLRequest(url: url))
        }
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let handler: ((URL) -> Void)?
        
        init(handler: ((URL) -> Void)?) {
            self.handler = handler
        }
        
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            print(#function, navigationAction.request.url ?? "nil")
            return .allow
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard handler != nil else { return }
            
            Task { @MainActor in
                let source = """
                    var src = document.querySelector("video")?.src
                    if (src) {
                        webkit.messageHandlers.\(handlerName).postMessage(src)
                    }
                    1
                    """
                var done = false
                while !done {
                    do {
                        _ = try await webView.evaluateJavaScript(source)
                        done = true
                    } catch {
                        print(#function, error)
                    }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
            }
        }
        
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            print(#function, message.body)
            guard let string = message.body as? String,
                  let url = URL(string: string) else { return }
            handler?(url)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(handler: handler)
    }
}

// MARK: - DownloadsView & DetailsView

struct DownloadsView: View {
    @EnvironmentObject var app: AppModel
    
    var body: some View {
        ForEach(app.downloads, id: \.self) { download in
            NavigationLink(download.lastPathComponent,
                           destination: DetailsView(url: download))
        }
    }
}

struct DetailsView: View {
    let url: URL
    
    @State var info: Info?
    @State var isExpanded = false
    @State var videoURL: URL?
    
    var body: some View {
        List {
            if let videoURL = videoURL {
                Section {
                    NavigationLink("Trim", destination: TrimView(url: videoURL))
                }
            }
            
            if let info = info {
                DisclosureGroup("\(info.formats.count) Formats", isExpanded: $isExpanded) {
                    ForEach(info.formats, id: \.format_id) { format in
                        Text(format.format)
                    }
                }
            }
        }
        .task {
            do {
                info = try JSONDecoder().decode(
                    Info.self,
                    from: try Data(contentsOf: url.appendingPathComponent("Info.json"))
                )
                
                videoURL = try FileManager.default
                    .contentsOfDirectory(
                        at: url,
                        includingPropertiesForKeys: [.contentTypeKey],
                        options: .skipsHiddenFiles
                    )
                    .first { url in
                        try! url.resourceValues(forKeys: [.contentTypeKey])
                            .contentType?.conforms(to: .movie) ?? false
                    }
            } catch {
                print(error)
            }
        }
    }
}

// MARK: - TaskList

struct TaskList: View {
    let tasks: [URLSessionDownloadTask]
    
    struct TaskGroup: Identifiable {
        let title: String?
        let task: URLSessionDownloadTask?
        let children: [TaskGroup]?
        
        var id: String? { task.map { "\($0.taskIdentifier)" } ?? title }
        var sortKey: Int { task?.taskIdentifier ?? -1 }
    }
    
    @State var groups: [TaskGroup] = []
    
    var body: some View {
        List(groups, children: \.children) { item in
            if let task = item.task {
                Text("#\(task.taskIdentifier) \(task.originalRequest?.value(forHTTPHeaderField: "Range") ?? "No range")")
            } else {
                Text(item.title ?? "nil")
            }
        }
        .onAppear {
            let groups = Dictionary(grouping: tasks) { task -> String? in
                guard let d = task.taskDescription,
                      let index = d.lastIndex(of: "-") else {
                    return task.taskDescription
                }
                return String(d[..<index])
            }
            .map { key, value -> TaskGroup in
                print(key ?? "nil", value.map(\.taskIdentifier))
                return TaskGroup(
                    title: key,
                    task: nil,
                    children: Dictionary(grouping: value, by: \.kind)
                        .map { key, value -> TaskGroup in
                            let children = value
                                .map { TaskGroup(title: nil, task: $0, children: nil) }
                                .sorted { $0.sortKey < $1.sortKey }
                            print(key, children.map(\.task?.taskIdentifier))
                            return TaskGroup(
                                title: key.description,
                                task: nil,
                                children: children
                            )
                        }
                )
            }
            
            self.groups = groups
        }
    }
}

// MARK: - Simple Browser

struct Browser: View {
    @State private var address = ""
    @State private var url = URL(string: "https://instagram.com")
    
    var body: some View {
        VStack {
            TextField("Address", text: $address)
                .onSubmit {
                    guard let url = URL(string: (address.hasPrefix("https://") ? "" : "https://") + address) else { return }
                    self.url = url
                }
                .textInputAutocapitalization(.never)
                .padding()
            WebView(url: url, handler: nil)
        }
    }
}
