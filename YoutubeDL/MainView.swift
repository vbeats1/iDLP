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

// Global alias so AppModel's TimeRange compiles
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
    @State var showSettings = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    // URL Input Section
                    Section {
                        HStack(spacing: 12) {
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
                            
                            Button {
                                let pasteBoard = UIPasteboard.general
                                guard let url = pasteBoard.url
                                        ?? pasteBoard.string.flatMap({ URL(string: $0) }) else {
                                    alert(message: "Nothing to paste")
                                    return
                                }
                                urlString = url.absoluteString
                                app.url = url
                            } label: {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.system(size: 16))
                            }
                            .buttonStyle(.borderless)
                        }
                    } header: {
                        Text("Media URL")
                    }
                    
                    // Quality Picker Section
                    Section {
                        Picker("Quality", selection: Binding(
                            get: { app.selectedFormatID ?? "best" },
                            set: { app.selectedFormatID = $0 }
                        )) {
                            ForEach(AppModel.predefinedFormats) { format in
                                Text(format.displayName).tag(format.id)
                            }
                        }
                        .pickerStyle(.menu)
                    } header: {
                        Text("Quality")
                    }
                    
                    // Activity Log Section
                    Section {
                        if app.logMessages.isEmpty {
                            HStack {
                                Spacer()
                                Text("No activity yet")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 20)
                                Spacer()
                            }
                        } else {
                            ScrollViewReader { proxy in
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 3) {
                                        ForEach(app.logMessages.suffix(50)) { logMessage in
                                            logMessageRow(logMessage)
                                                .id(logMessage.id)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                                .frame(height: 300)
                                .onChange(of: app.logMessages.count) { oldValue, newValue in
                                    scrollToLatest(proxy: proxy)
                                }
                                .onAppear {
                                    scrollToLatest(proxy: proxy)
                                }
                            }
                        }
                    } header: {
                        Text("Activity Log")
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                
                // Download Button at bottom
                VStack(spacing: 0) {
                    Divider()
                    Button {
                        guard let url = app.url ?? URL(string: urlString) else {
                            alert(message: "No valid URL")
                            return
                        }
                        Task {
                            await app.startDownload(url: url)
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if app.showProgress {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            } else {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 20))
                            }
                            Text(app.showProgress ? "Downloading..." : "Download")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(app.showProgress ? Color.gray : Color.accentColor)
                        )
                    }
                    .disabled((app.url == nil && URL(string: urlString) == nil) || app.showProgress)
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(Color(uiColor: .systemGroupedBackground))
                }
            }
            .navigationTitle("iDLP")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        app.fullReset()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .disabled(app.showProgress)
                    
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(app)
            }
            .onChange(of: app.url) { oldValue, newValue in
                guard let url = newValue else { return }
                urlString = url.absoluteString
            }
            .onReceive(app.$error) {
                error = $0
            }
            .alert(isPresented: $isShowingAlert) {
                Alert(
                    title: Text("Error"),
                    message: Text(alertMessage ?? "An unknown error occurred"),
                    dismissButton: .default(Text("OK"))
                )
            }
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
        }
    }
    
    // MARK: - View Components
    
    private func logMessageRow(_ logMessage: AppModel.LogMessage) -> some View {
        HStack(alignment: .top, spacing: 6) {
            // Terminal-style indicator (compact but readable)
            Circle()
                .fill(colorForLogLevel(logMessage.level))
                .frame(width: 5, height: 5)
                .padding(.top, 4)
            
            // Inline message with timestamp (terminal-style)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(logMessage.message)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(textColorForLogLevel(logMessage.level))
                    .textSelection(.enabled)
                    .lineLimit(nil)
                
                // Timestamp inline (smaller, more subtle)
                Text(logMessage.timestamp)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
    
    // MARK: - Helper Functions
    
    private func scrollToLatest(proxy: ScrollViewProxy) {
        if let lastMessage = app.logMessages.last {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
    
    func alert(message: String) {
        alertMessage = message
        isShowingAlert = true
    }
    
    // MARK: - Log Level Colors
    
    private func colorForLogLevel(_ level: AppModel.LogLevel) -> Color {
        switch level {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .debug: return .gray
        case .progress: return .blue
        case .success: return .green
        }
    }
    
    private func textColorForLogLevel(_ level: AppModel.LogLevel) -> Color {
        switch level {
        case .info: return .primary
        case .warning: return .orange
        case .error: return .red
        case .debug: return .secondary
        case .progress: return .blue
        case .success: return .green
        }
    }
}

// MARK: - WebView for Instagram fallback

struct WebView: UIViewControllerRepresentable {
    let url: URL
    let onURLFound: (URL) -> Void
    
    func makeUIViewController(context: Context) -> WebViewController {
        let controller = WebViewController()
        controller.url = url
        controller.onURLFound = onURLFound
        return controller
    }
    
    func updateUIViewController(_ uiViewController: WebViewController, context: Context) {}
}

class WebViewController: UIViewController, WKNavigationDelegate {
    var url: URL?
    var onURLFound: ((URL) -> Void)?
    var webView: WKWebView?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let webView = WKWebView()
        webView.navigationDelegate = self
        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        self.webView = webView
        
        if let url = url {
            webView.load(URLRequest(url: url))
        }
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url,
           url.host?.contains("instagram.com") == false {
            decisionHandler(.cancel)
            onURLFound?(url)
            dismiss(animated: true)
            return
        }
        decisionHandler(.allow)
    }
}
