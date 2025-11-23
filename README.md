# iDLP - iOS Video Downloader

<div align="center">

![iDLP Logo](YoutubeDL/Images.xcassets/AppIcon.appiconset/dlpicon.jpg)

**A powerful, native iOS application for downloading videos and audio from YouTube, SoundCloud, Instagram, and 1000+ other platforms**

[![Swift](https://img.shields.io/badge/Swift-5.0+-orange.svg)](https://swift.org)
[![iOS](https://img.shields.io/badge/iOS-26.0+-blue.svg)](https://developer.apple.com/ios/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

</div>

---

## 📱 Screenshots

<div align="center">

<table>
  <tr>
    <td align="center"><img src="https://i.imgur.com/lDl87Oi.png" width="200"/></td>
    <td align="center"><img src="https://i.imgur.com/9s4tFgq.png" width="200"/></td>
    <td align="center"><img src="https://i.imgur.com/mudA1va.png" width="200"/></td>
    <td align="center"><img src="https://i.imgur.com/bAvrxfn.png" width="200"/></td>
  </tr>
  <tr>
    <td align="center"><img src="https://i.imgur.com/8jpEU8G.png" width="200"/></td>
    <td align="center"><img src="https://i.imgur.com/7YO6XLG.png" width="200"/></td>
    <td align="center"><img src="https://i.imgur.com/tvZSH02.png" width="200"/></td>
    <td></td>
  </tr>
</table>

</div>

---

## ⚠️ Important Warning

**This app is NOT App Store-safe.** Apple has historically removed apps that download videos from YouTube and similar platforms. This app will likely be rejected by the App Store review process. It is intended for personal use, development, and side-loading via AltStore, Sideloadly, or similar tools.

**Legal Disclaimer**: This app is for educational and personal use only. Respect content creators' rights and platform terms of service. Downloading copyrighted content may violate terms of service and local laws. Use responsibly and at your own risk.

---

## ✨ Features

### Core Functionality

- **Multi-Platform Support**: Download from 1000+ platforms including YouTube, SoundCloud, Instagram, Twitter/X, TikTok, Vimeo, and any platform supported by [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- **Automatic yt-dlp Updates**: Automatically downloads the latest yt-dlp Python module from GitHub releases
- **Quality Selection**: 
  - Best Quality (Auto), Best Video Only, Best Audio Only, Worst Quality
  - Specific resolutions (720p, 480p, 360p)
  - Format-specific options (MP4, WebM, etc.)

### Advanced Features

- **Background Downloads**: Continue downloading when app is in background with completion notifications
- **FFmpeg Integration**: Embedded FFmpeg libraries for video/audio transcoding and stream merging
- **Metadata Embedding**: Embeds thumbnails and metadata into downloaded files
- **Progress Tracking**: Real-time download progress with detailed activity logs
- **SoundCloud OAuth**: Optional OAuth token support for higher quality SoundCloud downloads
- **URL Scheme Support**: Open app directly with `yhttps://` URLs
- **File Sharing**: Access downloaded files via iTunes File Sharing or Files app

---

## 🏗️ Architecture

### Components

- **AppDelegate** (`AppDelegate.swift`): Initializes Python runtime, FFmpeg support, window management, URL scheme handling
- **AppModel** (`AppModel.swift`): Core business logic, yt-dlp integration, download management, FFmpeg operations, logging system
- **MainView** (`MainView.swift`): Primary SwiftUI interface, URL input, quality selection, activity log display
- **SettingsView** (`SettingsView.swift`): SoundCloud OAuth token configuration

### Technical Stack

- **Language**: Swift 5.0+
- **UI Framework**: SwiftUI (iOS 13.0+)
- **Python Integration**: [Python-iOS](https://github.com/kewlbear/Python-iOS) with PythonKit
- **Video Processing**: [FFmpeg-iOS](https://github.com/kewlbear/FFmpeg-iOS) with embedded libraries
- **Download Engine**: URLSession with background download support
- **Architecture**: MVVM with ObservableObject, MainActor for thread safety
- **Dependencies**: Swift Package Manager

### Download Process

1. URL input & validation
2. Format detection via yt-dlp
3. Format selection based on user preference
4. Download initiation with URLSession
5. Stream merging (if needed) using FFmpeg
6. Transcoding (if needed)
7. Metadata embedding (thumbnails, titles, etc.)
8. File management and completion notification

---

## 📦 Installation

### Prerequisites

- macOS with Xcode 14.0+
- iOS Deployment Target: iOS 26.0
- Apple Developer Account (free account works for development)
- Swift Package Manager (built into Xcode)

### Steps

1. **Clone Repository**
   ```bash
   git clone https://github.com/yourusername/YTDLP-iOS26.git
   cd YTDLP-iOS26
   ```

2. **Open Project**
   ```bash
   open YoutubeDL.xcodeproj
   ```

3. **Install Dependencies**
   - Xcode will automatically resolve Swift packages
   - Required: Python-iOS, FFmpeg-iOS, YoutubeDL-iOS

4. **Configure Code Signing**
   - Select project → Target → Signing & Capabilities
   - Enable "Automatically manage signing"
   - Select your Team (Apple ID)

5. **Build and Run**
   - Select target device (Simulator or physical device)
   - Press `Cmd + R` to build and run
   - First launch downloads yt-dlp (may take time)

### Building for Physical Device

1. Connect device via USB
2. Select device in Xcode
3. Ensure Apple ID is added in Xcode → Preferences → Accounts
4. Build and run
5. Trust developer on device: Settings → General → VPN & Device Management

### Creating IPA

1. **Archive**: Product → Archive in Xcode
2. **Export**: In Organizer, select archive → Distribute App
3. **Choose Method**: Ad Hoc, Development, or Enterprise
4. **Install**: Use AltStore, Sideloadly, or Xcode

Or use command line:
```bash
xcodebuild archive -project YoutubeDL.xcodeproj -scheme YoutubeDL -archivePath build/YoutubeDL.xcarchive
xcodebuild -exportArchive -archivePath build/YoutubeDL.xcarchive -exportPath build -exportOptionsPlist ExportOptions.plist
```

---

## 🚀 Usage

### Basic Usage

1. Launch app
2. Enter URL (or paste from clipboard)
3. Select quality from picker
4. Tap Download
5. Monitor progress in activity log
6. Access files in Documents directory via iTunes File Sharing or Files app

### SoundCloud OAuth Token

For higher quality SoundCloud downloads:

1. Open Settings (gear icon)
2. Visit soundcloud.com in desktop browser and log in
3. Open Developer Tools (F12 or Cmd+Option+I)
4. Go to Application/Storage → Cookies → soundcloud.com
5. Find `oauth_token` cookie and copy value
6. Paste token in Settings and tap "Save Token"

### URL Scheme

Use `yhttps://` scheme to open app directly:
- Example: `yhttps://youtube.com/watch?v=...`
- App automatically converts to `https://` and starts download

### Supported Platforms

All platforms supported by [yt-dlp](https://github.com/yt-dlp/yt-dlp), including:
- YouTube, SoundCloud, Instagram, Twitter/X, TikTok, Vimeo, Dailymotion, Twitch, Facebook, Reddit, and 1000+ more

---

## 🔧 Configuration

### Key Files

- **`YoutubeDL-Info.plist`**: App configuration, URL schemes, permissions
- **`YoutubeDL.entitlements`**: App capabilities, background modes
- **`ExportOptions.plist`**: IPA export configuration

### Permissions

- **Photo Library**: Save downloaded videos to Photos
- **Network Access**: Download media and yt-dlp updates
- **Background Modes**: Continue downloads in background

### Build Settings

- Deployment Target: iOS 26.0
- Swift Version: 5.0+
- Architecture: arm64
- Bitcode: Disabled (required for FFmpeg)

---

## 📚 Dependencies

### Swift Packages

- **[Python-iOS](https://github.com/kewlbear/Python-iOS)**: Python runtime for iOS
- **[FFmpeg-iOS](https://github.com/kewlbear/FFmpeg-iOS)**: Embedded FFmpeg libraries (avcodec, avformat, avfilter, etc.)
- **[YoutubeDL-iOS](https://github.com/kewlbear/YoutubeDL-iOS)**: Swift wrapper for yt-dlp

### System Frameworks

UIKit, SwiftUI, AVFoundation, UserNotifications, WebKit, Combine, Foundation

---

## 🐛 Troubleshooting

### App Won't Launch

- Check dependencies: File → Packages → Resolve Package Versions
- Clean build: Product → Clean Build Folder (`Cmd+Shift+K`)
- Verify code signing configuration
- Check network connection (first launch downloads yt-dlp)

### Downloads Fail

- Verify internet connection
- Check URL is valid and accessible
- Review activity log for specific errors
- Try different quality setting
- Ensure yt-dlp downloaded successfully (check activity log)

### FFmpeg Errors

- Verify FFmpeg frameworks are embedded
- Check device has sufficient storage space
- Review activity log for specific error messages

### SoundCloud Downloads Fail

- Add OAuth token in Settings
- Verify token is valid and not expired
- Some content may be region-locked or require subscription

### Common Error Messages

- "Python not initialized": Python runtime failed to initialize
- "yt-dlp not found": yt-dlp download failed or incomplete
- "Format not available": Selected format not available for this video
- "Network error": Internet connection issue
- "Storage full": Device storage is full

---

## 📝 Development

### Project Structure

```
YTDLP-iOS26/
├── YoutubeDL/                 # Main app source
│   ├── AppDelegate.swift      # App lifecycle
│   ├── AppModel.swift         # Core logic (1920 lines)
│   ├── MainView.swift         # Main UI
│   ├── SettingsView.swift     # Settings UI
│   └── YoutubeDL-Info.plist   # App config
├── YoutubeDL.xcodeproj/       # Xcode project
└── README.md                  # This file
```

### Code Style

- Follow Swift API Design Guidelines
- Use SwiftUI best practices
- Use `@MainActor` for UI-related code
- Add comments for complex logic

### Contributing

1. Fork the repository
2. Create feature branch: `git checkout -b feature/your-feature`
3. Make changes and test thoroughly
4. Commit: `git commit -m "Add: Description"`
5. Push: `git push origin feature/your-feature`
6. Submit pull request

---

## 📄 License

MIT License - See [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- Original work by [Changbeom Ahn](https://github.com/kewlbear)
- Built on [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- Uses [FFmpeg](https://ffmpeg.org/) for video processing
- Dependencies: [Python-iOS](https://github.com/kewlbear/Python-iOS), [FFmpeg-iOS](https://github.com/kewlbear/FFmpeg-iOS), [YoutubeDL-iOS](https://github.com/kewlbear/YoutubeDL-iOS)

---

## 🔗 Links

- **yt-dlp**: [https://github.com/yt-dlp/yt-dlp](https://github.com/yt-dlp/yt-dlp)
- **FFmpeg**: [https://ffmpeg.org/](https://ffmpeg.org/)
- **Python-iOS**: [https://github.com/kewlbear/Python-iOS](https://github.com/kewlbear/Python-iOS)
- **FFmpeg-iOS**: [https://github.com/kewlbear/FFmpeg-iOS](https://github.com/kewlbear/FFmpeg-iOS)

---

<div align="center">

**Made with ❤️ for the iOS community**

</div>
