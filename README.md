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

![Main Interface](Images/Screen%20Shot%201.png)
*Main download interface with URL input and quality selection*

![Activity Log](Images/Screen%20Shot%202.png)
*Real-time activity log showing download progress*

![Settings](Images/Screen%20Shot%203.png)
*Settings panel for SoundCloud OAuth configuration*

![Download Complete](Images/Screen%20Shot%204.png)
*Download completion notification and file management*

</div>

---

## ⚠️ Important Warning

**This app is NOT App Store-safe.** 

Apple has historically removed apps that download videos from YouTube and similar platforms. This app will likely be rejected by the App Store review process. It is intended for:

- Personal use and development purposes
- Educational purposes
- Testing and experimentation
- Side-loading via AltStore, Sideloadly, or similar tools

**Legal Disclaimer**: This app is for educational and personal use only. Respect content creators' rights and platform terms of service. Downloading copyrighted content may violate terms of service and local laws. Use responsibly and at your own risk.

---

## ✨ Features

### 🎯 Core Functionality

- **Multi-Platform Support**: Download videos and audio from 1000+ platforms including:
  - YouTube (videos, playlists, channels)
  - SoundCloud (tracks, playlists, albums)
  - Instagram (posts, stories, reels)
  - Twitter/X (videos, tweets)
  - TikTok (videos)
  - Vimeo, Dailymotion, and many more
  - Any platform supported by [yt-dlp](https://github.com/yt-dlp/yt-dlp)

- **Automatic yt-dlp Updates**: 
  - Automatically downloads the latest yt-dlp Python module from GitHub releases
  - No manual updates required
  - Always uses the most recent version with latest fixes and features

- **Intelligent Quality Selection**: 
  - **Best Quality (Auto)**: Automatically selects the best available format
  - **Best Video Only**: Downloads only the video stream (no audio)
  - **Best Audio Only**: Downloads only the audio stream (no video)
  - **Worst Quality**: Downloads the smallest/lowest quality version
  - **Specific Resolutions**: Choose from 720p, 480p, 360p, and more
  - **Format-Specific**: Select MP4, WebM, or other specific formats
  - **Custom Format Strings**: Advanced users can specify custom format strings

### 🚀 Advanced Features

- **Background Downloads**: 
  - Downloads continue even when the app is in the background
  - Supports iOS background download tasks
  - Notifications when downloads complete

- **Chunk-Based Downloads**: 
  - Efficient download system using URLSession with chunk support
  - Resumable downloads (if supported by server)
  - Progress tracking for large files

- **FFmpeg Integration**: 
  - Embedded FFmpeg libraries for video/audio transcoding
  - No external dependencies required
  - Supports all FFmpeg codecs and formats

- **Stream Merging**: 
  - Automatically combines separate video and audio streams when needed
  - Handles cases where platforms serve video and audio separately
  - Seamless merging with progress tracking

- **Metadata Embedding**: 
  - Embeds thumbnails into downloaded files
  - Preserves video metadata (title, description, uploader, etc.)
  - Creates proper file names based on video titles

- **Progress Tracking**: 
  - Real-time download progress with percentage and speed
  - Detailed activity logs with color-coded messages
  - Terminal-style log viewer with scrollback

- **SoundCloud OAuth**: 
  - Optional OAuth token support for higher quality SoundCloud downloads
  - Easy token configuration in Settings
  - Secure token storage

- **URL Scheme Support**: 
  - Open the app directly from URLs using the `yhttps://` scheme
  - Share URLs from other apps directly to iDLP
  - Automatic URL conversion and processing

- **File Sharing**: 
  - Access downloaded files via iTunes File Sharing
  - Files saved to app's Documents directory
  - Easy export to other apps

### 🎨 User Interface

- **Modern SwiftUI Design**: 
  - Clean, native iOS interface
  - Follows iOS Human Interface Guidelines
  - Dark mode support
  - Responsive layout for all screen sizes

- **Activity Log**: 
  - Terminal-style log viewer
  - Color-coded messages (info, warning, error, success)
  - Real-time updates
  - Scrollable history

- **Settings Panel**: 
  - Configure SoundCloud OAuth tokens
  - User preferences management
  - Glass morphism design

- **Paste from Clipboard**: 
  - Quick URL input from clipboard
  - One-tap paste button
  - Automatic URL validation

- **Notifications**: 
  - Background download completion notifications
  - Progress updates (optional)
  - Error notifications

---

## 🏗️ Architecture & Technical Details

### System Architecture

iDLP is built using a modern SwiftUI-based architecture with the following key components:

#### 1. **AppDelegate** (`AppDelegate.swift`)
   - **Initialization**: Sets up Python runtime and FFmpeg support
   - **Window Management**: Creates the main window programmatically (no storyboards)
   - **URL Scheme Handling**: Processes `yhttps://` URLs
   - **Notification Delegates**: Manages background notifications
   - **Lifecycle Management**: Handles app lifecycle events

#### 2. **AppModel** (`AppModel.swift`)
   - **Core Business Logic**: Central state management using `ObservableObject`
   - **yt-dlp Integration**: Wraps Python yt-dlp library with Swift interface
   - **Download Management**: 
     - Handles download operations with URLSession
     - Manages background download tasks
     - Tracks download progress
   - **Format Selection**: 
     - Analyzes available formats from yt-dlp
     - Selects appropriate format based on user preference
     - Handles format merging when needed
   - **FFmpeg Operations**: 
     - Coordinates transcoding operations
     - Manages stream merging
     - Handles metadata embedding
   - **Logging System**: 
     - Structured logging with levels (info, warning, error, debug, progress, success)
     - Thread-safe log message storage
     - Real-time log updates for UI

#### 3. **MainView** (`MainView.swift`)
   - **Primary UI**: Main user interface built with SwiftUI
   - **URL Input**: Text field with clipboard paste support
   - **Quality Selection**: Picker for format/quality selection
   - **Activity Log Display**: Scrollable log viewer with color coding
   - **Download Controls**: Start/stop download buttons
   - **Progress Indicators**: Real-time progress bars and percentages
   - **WebView Integration**: Fallback WebView for Instagram downloads

#### 4. **SettingsView** (`SettingsView.swift`)
   - **SoundCloud OAuth**: Token input and management
   - **User Preferences**: Settings storage and retrieval
   - **Modern UI**: Glass morphism design with blur effects

### Technical Stack

- **Language**: Swift 5.0+
- **UI Framework**: SwiftUI (iOS 13.0+)
- **Python Integration**: 
  - [Python-iOS](https://github.com/kewlbear/Python-iOS) framework
  - PythonKit for Swift-Python interop
  - Embedded Python runtime
- **Video Processing**: 
  - [FFmpeg-iOS](https://github.com/kewlbear/FFmpeg-iOS) framework
  - Embedded FFmpeg libraries (avcodec, avformat, avfilter, etc.)
  - Full codec support
- **Download Engine**: 
  - URLSession with background download support
  - Chunk-based downloads
  - Progress tracking
- **Architecture Pattern**: 
  - MVVM (Model-View-ViewModel)
  - ObservableObject for state management
  - MainActor for thread safety
- **Dependencies**: Swift Package Manager

### Download Process Flow

The download process follows these steps:

1. **URL Input & Validation**
   - User enters or pastes a media URL
   - App validates URL format
   - Converts `yhttps://` scheme to `https://` if needed

2. **Format Detection**
   - yt-dlp analyzes the URL
   - Extracts available formats and metadata
   - Lists video/audio codecs, resolutions, and bitrates

3. **Format Selection**
   - App selects the best format based on user preference
   - Handles cases where video and audio are separate streams
   - Falls back to alternative formats if primary selection fails

4. **Download Initiation**
   - Creates URLSession download task
   - Supports background downloads
   - Starts progress tracking

5. **Download Execution**
   - Downloads media using URLSession
   - Supports chunk-based downloads for large files
   - Updates progress in real-time
   - Handles network interruptions

6. **Stream Merging** (if needed)
   - Detects if video and audio are separate files
   - Uses FFmpeg to merge streams
   - Shows merge progress

7. **Transcoding** (if needed)
   - Transcodes to desired format if necessary
   - Uses FFmpeg for format conversion
   - Maintains quality during conversion

8. **Metadata Embedding**
   - Downloads video thumbnail
   - Embeds thumbnail into video file
   - Adds metadata (title, description, uploader, etc.)
   - Creates proper file name from video title

9. **File Management**
   - Saves file to app's Documents directory
   - Creates proper file name (sanitized)
   - Updates file system

10. **Completion**
    - Sends notification to user
    - Updates UI with success message
    - Logs completion to activity log

### Thread Safety

All UI updates are performed on the main thread using:
- `@MainActor` annotation on `AppModel`
- `DispatchQueue.main.async` for background operations
- Thread-safe property updates
- Proper synchronization for shared state

---

## 📦 Installation

### Prerequisites

- **macOS**: Latest version with Xcode installed
- **Xcode**: Version 14.0 or later (recommended: latest version)
- **iOS Deployment Target**: iOS 26.0 (as configured in project)
- **Apple Developer Account**: 
  - Required for code signing
  - Free account works for development
  - Paid account needed for distribution
- **Swift Package Manager**: Built into Xcode (no separate installation needed)

### Step-by-Step Installation

#### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/YTDLP-iOS26.git
cd YTDLP-iOS26
```

#### 2. Open the Project

```bash
open YoutubeDL.xcodeproj
```

Or double-click `YoutubeDL.xcodeproj` in Finder.

#### 3. Install Dependencies

The project uses Swift Package Manager. Xcode should automatically resolve dependencies when you open the project. If not:

1. Go to **File → Packages → Resolve Package Versions**
2. Wait for packages to download

The required packages are:
- [Python-iOS](https://github.com/kewlbear/Python-iOS) - Python runtime for iOS
- [FFmpeg-iOS](https://github.com/kewlbear/FFmpeg-iOS) - FFmpeg libraries
- [YoutubeDL-iOS](https://github.com/kewlbear/YoutubeDL-iOS) - Swift wrapper for yt-dlp

#### 4. Configure Code Signing

1. Select the **YoutubeDL** project in the navigator
2. Select the **YoutubeDL** target
3. Go to **Signing & Capabilities** tab
4. Check **"Automatically manage signing"**
5. Select your **Team** (your Apple ID)
6. Xcode will automatically create/manage provisioning profiles

#### 5. Change Bundle Identifier (Recommended)

To avoid conflicts with other apps:

1. In **Signing & Capabilities**, find **Bundle Identifier**
2. Change from default to something unique (e.g., `com.yourname.idlp`)
3. Xcode will update the provisioning profile automatically

#### 6. Build and Run

1. Select your target device:
   - **iOS Simulator**: Choose any iPhone/iPad simulator
   - **Physical Device**: Connect via USB and select your device
2. Press `Cmd + R` or click the **Run** button
3. Wait for the app to build and launch

**Note**: First launch may take longer as the app downloads yt-dlp from GitHub.

### Building for Physical Device

To run on a physical iOS device:

1. **Connect Device**: 
   - Connect your iOS device via USB
   - Trust the computer on your device if prompted
   - Unlock your device

2. **Select Device**: 
   - In Xcode, select your device from the device list (top toolbar)
   - If device doesn't appear, check USB connection

3. **Configure Signing**: 
   - Ensure your Apple ID is added in **Xcode → Preferences → Accounts**
   - Select your development team in **Signing & Capabilities**
   - Xcode will handle code signing automatically

4. **Build and Run**: 
   - Press `Cmd + R` to build and run
   - On first launch, you may need to trust the developer on your device:
     - Go to **Settings → General → VPN & Device Management**
     - Tap your developer account
     - Tap **Trust**

### Creating an IPA for Distribution

To create an IPA file for side-loading:

#### Method 1: Archive and Export (Recommended)

1. **Archive the App**:
   - In Xcode: **Product → Archive**
   - Wait for the archive to complete (may take several minutes)
   - Organizer window will open automatically

2. **Export the IPA**:
   - In the Organizer window, select your archive
   - Click **"Distribute App"**
   - Choose distribution method:
     - **Ad Hoc**: For installing on specific devices (requires device UDIDs)
     - **Development**: For testing on your devices
     - **Enterprise**: For enterprise distribution (requires enterprise account)
   - Follow the prompts to export the IPA file
   - Choose a location to save the IPA

3. **Install on Device**:
   - Use tools like [AltStore](https://altstore.io/), [Sideloadly](https://sideloadly.io/), or Xcode
   - For Ad Hoc distribution, add device UDIDs to your provisioning profile first

#### Method 2: Using ExportOptions.plist

The project includes an `ExportOptions.plist` file for automated exports:

```bash
# Archive the app
xcodebuild archive \
  -project YoutubeDL.xcodeproj \
  -scheme YoutubeDL \
  -archivePath build/YoutubeDL.xcarchive

# Export IPA
xcodebuild -exportArchive \
  -archivePath build/YoutubeDL.xcarchive \
  -exportPath build \
  -exportOptionsPlist ExportOptions.plist
```

---

## 🚀 Usage Guide

### Basic Usage

#### Downloading a Video

1. **Launch the App**: Open iDLP on your iOS device
2. **Enter URL**: 
   - Type a media URL in the text field, or
   - Tap the clipboard icon (📋) to paste from clipboard
   - Supported formats: `https://`, `http://`, or `yhttps://`
3. **Select Quality**: 
   - Choose your preferred quality from the picker
   - Options include: Best Quality, Best Video, Best Audio, specific resolutions, etc.
4. **Start Download**: 
   - Tap the **"Download"** button
   - The download will start immediately
5. **Monitor Progress**: 
   - Watch the activity log for real-time progress
   - Progress bar shows download percentage
   - Speed indicator shows download speed
6. **Access Files**: 
   - Downloaded files are saved in the app's Documents directory
   - Access via iTunes File Sharing or Files app

#### Example URLs

- YouTube: `https://www.youtube.com/watch?v=dQw4w9WgXcQ`
- SoundCloud: `https://soundcloud.com/artist/track-name`
- Instagram: `https://www.instagram.com/p/ABC123/`
- Twitter: `https://twitter.com/user/status/1234567890`

### Advanced Features

#### SoundCloud OAuth Token

For higher quality SoundCloud downloads, you can add an OAuth token:

1. **Open Settings**: 
   - Tap the gear icon (⚙️) in the navigation bar
   - Or go to Settings from the main menu

2. **Get OAuth Token**:
   - Visit [soundcloud.com](https://soundcloud.com) in a desktop browser
   - Log in to your account
   - Open browser Developer Tools:
     - **Chrome/Edge**: Press `F12` or `Ctrl+Shift+I` (Windows) / `Cmd+Option+I` (Mac)
     - **Firefox**: Press `F12` or `Ctrl+Shift+I` (Windows) / `Cmd+Option+I` (Mac)
     - **Safari**: Enable Developer menu first (Preferences → Advanced → Show Develop menu), then `Cmd+Option+I`
   - Navigate to **Application** (Chrome) or **Storage** (Firefox) tab
   - Go to **Cookies → https://soundcloud.com**
   - Find the `oauth_token` cookie
   - Copy its value

3. **Add Token in App**:
   - Paste the token in the Settings screen
   - Tap **"Save Token"**
   - Token will be saved securely

4. **Verify**: 
   - The button will show "Token Saved" when successful
   - You can clear the token anytime by tapping "Clear"

**Note**: The OAuth token is stored locally on your device and never transmitted except to SoundCloud for authentication.

#### URL Scheme

You can open the app directly with a URL using the custom URL scheme:

- **Format**: `yhttps://` (instead of `https://`)
- **Example**: `yhttps://youtube.com/watch?v=dQw4w9WgXcQ`
- **Usage**: 
  - Share URLs from other apps using the `yhttps://` scheme
  - The app will automatically convert to `https://` and start the download
  - Useful for quick downloads from Safari or other apps

#### Background Downloads

- Downloads continue when the app is in the background
- You'll receive a notification when the download completes
- Progress is saved, so you can close the app and reopen it later
- Large downloads are automatically handled in the background

#### File Management

- **Location**: All files are saved to the app's Documents directory
- **Access Methods**:
  - **iTunes File Sharing**: Connect device to computer, open iTunes, go to device → File Sharing → iDLP
  - **Files App**: Open Files app, navigate to "On My iPhone" → iDLP
  - **Export**: Share files to other apps using iOS share sheet

### Supported Platforms

iDLP supports all platforms that [yt-dlp](https://github.com/yt-dlp/yt-dlp) supports, including:

**Video Platforms**:
- YouTube (videos, playlists, channels, live streams)
- Vimeo
- Dailymotion
- Twitch
- TikTok
- Instagram (posts, stories, reels, IGTV)
- Twitter/X
- Facebook
- Reddit
- And 1000+ more...

**Audio Platforms**:
- SoundCloud
- Spotify (via external tools)
- Bandcamp
- Mixcloud
- And many more...

**Note**: Platform support depends on yt-dlp updates. The app automatically uses the latest yt-dlp version.

---

## 🔧 Configuration

### Project Settings

Key configuration files:

- **`YoutubeDL-Info.plist`**: 
  - App configuration and metadata
  - URL schemes (`yhttps://`)
  - Permissions (Photo Library, etc.)
  - Document types
  - Bundle identifier

- **`YoutubeDL.entitlements`**: 
  - App capabilities
  - Background modes
  - Keychain access groups

- **`ExportOptions.plist`**: 
  - IPA export configuration
  - Distribution method settings
  - Code signing options

### Permissions

The app requires the following permissions:

- **Photo Library Access**: 
  - Purpose: To save downloaded videos to Photos
  - Requested when user tries to save a video
  - Can be denied by user

- **Network Access**: 
  - Purpose: To download media and yt-dlp updates
  - Required for app functionality
  - Configured in Info.plist

- **Background Modes**: 
  - Purpose: For background downloads
  - Configured in entitlements
  - Allows downloads to continue when app is backgrounded

### Build Settings

Key build settings in the project:

- **Deployment Target**: iOS 26.0
- **Swift Version**: Latest (5.0+)
- **Architecture**: arm64 (iOS devices)
- **Code Signing**: Automatic
- **Bitcode**: Disabled (required for FFmpeg)

---

## 📚 Dependencies

### Swift Packages

#### Python-iOS
- **Repository**: [kewlbear/Python-iOS](https://github.com/kewlbear/Python-iOS)
- **Purpose**: Provides Python runtime for iOS
- **Usage**: Enables running yt-dlp Python scripts natively
- **Version**: Managed by Swift Package Manager

#### FFmpeg-iOS
- **Repository**: [kewlbear/FFmpeg-iOS](https://github.com/kewlbear/FFmpeg-iOS)
- **Purpose**: Embedded FFmpeg libraries
- **Usage**: Handles video/audio transcoding and merging
- **Components**: 
  - avcodec (encoding/decoding)
  - avformat (container formats)
  - avfilter (filtering)
  - avutil (utilities)
  - swscale (scaling)
  - swresample (resampling)
- **Version**: Managed by Swift Package Manager

#### YoutubeDL-iOS
- **Repository**: [kewlbear/YoutubeDL-iOS](https://github.com/kewlbear/YoutubeDL-iOS)
- **Purpose**: Swift wrapper for yt-dlp
- **Usage**: Provides native Swift interface to yt-dlp functionality
- **Version**: Managed by Swift Package Manager

### System Frameworks

- **UIKit**: Core iOS UI framework (for AppDelegate)
- **SwiftUI**: Modern declarative UI framework (for views)
- **AVFoundation**: Media processing and playback
- **UserNotifications**: Background notifications
- **WebKit**: Web view for Instagram fallback
- **Combine**: Reactive programming for state management
- **Foundation**: Core functionality (URLSession, FileManager, etc.)

---

## 🐛 Troubleshooting

### Common Issues

#### App Won't Launch / Black Screen

**Symptoms**: App opens but shows black screen or crashes immediately

**Solutions**:
1. **Check Window Initialization**: 
   - Ensure `window` is properly initialized in `AppDelegate`
   - Verify `makeKeyAndVisible()` is called

2. **Check Dependencies**: 
   - Ensure all Swift packages are resolved
   - Go to **File → Packages → Resolve Package Versions**
   - Clean build folder: **Product → Clean Build Folder** (`Cmd+Shift+K`)

3. **Check Code Signing**: 
   - Verify code signing is configured correctly
   - Check that your development team is selected
   - Ensure provisioning profile is valid

4. **Check Python Initialization**: 
   - First launch downloads yt-dlp, which may take time
   - Check network connection
   - Review activity log for errors

#### Downloads Fail

**Symptoms**: Downloads start but fail with errors

**Solutions**:
1. **Check Internet Connection**: 
   - Ensure device has active internet connection
   - Try downloading from a different network

2. **Verify URL**: 
   - Ensure the URL is valid and accessible
   - Try opening URL in Safari to verify it works
   - Some URLs may be region-locked or require authentication

3. **Check yt-dlp**: 
   - First launch automatically downloads yt-dlp
   - If download fails, check network connection
   - Review activity log for yt-dlp download errors
   - yt-dlp is downloaded from GitHub releases

4. **Review Activity Log**: 
   - Check the activity log for specific error messages
   - Common errors:
     - "Video unavailable": Content may be deleted or private
     - "Private video": Requires authentication
     - "Region blocked": Content not available in your region
     - "Format not available": Selected format not available for this video

5. **Try Different Quality**: 
   - Some formats may not be available
   - Try selecting "Best Quality (Auto)" for automatic selection

#### FFmpeg Errors

**Symptoms**: Downloads succeed but merging/transcoding fails

**Solutions**:
1. **Check FFmpeg Frameworks**: 
   - Ensure FFmpeg frameworks are properly embedded
   - Check that frameworks are in "Frameworks, Libraries, and Embedded Content"
   - Verify frameworks are not missing

2. **Check Storage Space**: 
   - Ensure device has sufficient storage space
   - FFmpeg operations require temporary storage
   - Free up space if needed

3. **Check File Permissions**: 
   - Verify app has write permissions to Documents directory
   - Check that files are not locked or in use

4. **Review Logs**: 
   - Check activity log for specific FFmpeg error messages
   - Common errors indicate codec or format issues

#### SoundCloud Downloads Fail

**Symptoms**: SoundCloud downloads fail or download low quality

**Solutions**:
1. **Add OAuth Token**: 
   - SoundCloud may require authentication for some content
   - Add OAuth token in Settings (see Advanced Features section)
   - Token enables higher quality downloads

2. **Check Content Availability**: 
   - Some SoundCloud content may be region-locked
   - Some tracks may require SoundCloud Go subscription
   - Try different tracks to verify

3. **Verify Token**: 
   - Ensure OAuth token is valid and not expired
   - Re-enter token if downloads continue to fail
   - Token may expire after some time

#### App Crashes

**Symptoms**: App crashes during download or other operations

**Solutions**:
1. **Check Memory**: 
   - Large downloads may use significant memory
   - Close other apps to free memory
   - Try downloading smaller files first

2. **Check Logs**: 
   - Review Xcode console for crash logs
   - Check system logs in Console.app on macOS
   - Look for specific error messages

3. **Update Dependencies**: 
   - Ensure all Swift packages are up to date
   - Update to latest versions if available

4. **Clean Build**: 
   - Clean build folder: **Product → Clean Build Folder**
   - Delete DerivedData folder
   - Rebuild project

### Debugging

#### Enable Detailed Logging

The app includes a comprehensive logging system:

1. **Activity Log**: 
   - View real-time logs in the app's activity log
   - Logs are color-coded by level (info, warning, error, success)
   - Scroll to see full history

2. **Xcode Console**: 
   - Connect device to Xcode
   - View console output in Xcode
   - Filter logs by app name

3. **System Logs**: 
   - Use Console.app on macOS
   - Filter by app name or process
   - View detailed system logs

#### Common Error Messages

- **"Python not initialized"**: Python runtime failed to initialize
- **"yt-dlp not found"**: yt-dlp download failed or incomplete
- **"Format not available"**: Selected format not available for this video
- **"Network error"**: Internet connection issue
- **"Storage full"**: Device storage is full
- **"Permission denied"**: File system permission issue

---

## 📝 Development

### Project Structure

```
YTDLP-iOS26/
├── YoutubeDL/                      # Main app source code
│   ├── AppDelegate.swift           # App lifecycle and initialization
│   ├── AppModel.swift              # Core business logic (1920 lines)
│   ├── MainView.swift              # Main UI
│   ├── SettingsView.swift          # Settings UI
│   ├── YoutubeDL-Bridging-Header.h # Objective-C bridging header
│   ├── YoutubeDL-Info.plist        # App configuration
│   ├── YoutubeDL.entitlements      # App capabilities
│   ├── LaunchScreen.storyboard     # Launch screen
│   ├── Images.xcassets/            # App icons and images
│   │   └── AppIcon.appiconset/     # App icons
│   ├── Base.lproj/                 # Base localization
│   ├── en.lproj/                   # English localization
│   └── ko.lproj/                   # Korean localization
├── YoutubeDL.xcodeproj/            # Xcode project files
│   ├── project.pbxproj             # Project configuration
│   ├── project.xcworkspace/        # Workspace settings
│   └── xcshareddata/               # Shared schemes
├── YoutubeDLTests/                 # Unit tests
│   └── YoutubeDLTests.swift
├── Images/                         # Screenshots for README
│   ├── Screen Shot 1.png
│   ├── Screen Shot 2.png
│   ├── Screen Shot 3.png
│   └── Screen Shot 4.png
├── build/                          # Build artifacts (gitignored)
├── ExportOptions.plist             # IPA export configuration
├── LICENSE                         # MIT License
└── README.md                       # This file
```

### Key Files

- **`AppModel.swift`** (1920 lines): 
  - Core business logic
  - Download management
  - Format selection
  - FFmpeg operations
  - Logging system

- **`MainView.swift`**: 
  - Primary user interface
  - URL input and validation
  - Quality selection
  - Activity log display
  - Download controls

- **`AppDelegate.swift`**: 
  - App initialization
  - Python and FFmpeg setup
  - Window management
  - URL scheme handling

### Code Style

- **Swift API Design Guidelines**: Follow Apple's Swift API Design Guidelines
- **SwiftUI Best Practices**: Use SwiftUI patterns and conventions
- **Thread Safety**: 
  - Use `@MainActor` for UI-related code
  - Use `DispatchQueue.main.async` for main thread updates
  - Avoid blocking the main thread
- **Comments**: 
  - Add comments for complex logic
  - Document public APIs
  - Explain non-obvious code

### Contributing

Contributions are welcome! To contribute:

1. **Fork the Repository**: 
   - Fork the repository on GitHub
   - Clone your fork locally

2. **Create a Feature Branch**: 
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make Your Changes**: 
   - Write clean, well-commented code
   - Follow the existing code style
   - Test thoroughly

4. **Test Your Changes**: 
   - Test on multiple devices if possible
   - Test different scenarios
   - Verify no regressions

5. **Commit Your Changes**: 
   ```bash
   git commit -m "Add: Description of your feature"
   ```

6. **Push to Your Fork**: 
   ```bash
   git push origin feature/your-feature-name
   ```

7. **Submit a Pull Request**: 
   - Open a pull request on GitHub
   - Describe your changes clearly
   - Reference any related issues

### Building from Source

1. Clone the repository
2. Open `YoutubeDL.xcodeproj` in Xcode
3. Resolve Swift packages (automatic)
4. Configure code signing
5. Build and run

---

## 📄 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

**MIT License Summary**:
- ✅ Commercial use
- ✅ Modification
- ✅ Distribution
- ✅ Private use
- ❌ Liability
- ❌ Warranty

---

## 🙏 Acknowledgments

- **Original Work**: Based on work by [Changbeom Ahn](https://github.com/kewlbear)
- **yt-dlp**: Built on [yt-dlp](https://github.com/yt-dlp/yt-dlp) by the yt-dlp team
- **FFmpeg**: Uses [FFmpeg](https://ffmpeg.org/) for video processing
- **Python-iOS**: Python runtime via [Python-iOS](https://github.com/kewlbear/Python-iOS)
- **FFmpeg-iOS**: FFmpeg libraries via [FFmpeg-iOS](https://github.com/kewlbear/FFmpeg-iOS)
- **YoutubeDL-iOS**: Swift wrapper via [YoutubeDL-iOS](https://github.com/kewlbear/YoutubeDL-iOS)

---

## 🔗 Links

- **GitHub Repository**: [Your Repository URL]
- **yt-dlp**: [https://github.com/yt-dlp/yt-dlp](https://github.com/yt-dlp/yt-dlp)
- **FFmpeg**: [https://ffmpeg.org/](https://ffmpeg.org/)
- **Python-iOS**: [https://github.com/kewlbear/Python-iOS](https://github.com/kewlbear/Python-iOS)
- **FFmpeg-iOS**: [https://github.com/kewlbear/FFmpeg-iOS](https://github.com/kewlbear/FFmpeg-iOS)

---

## 📊 Project Status

- ✅ Core download functionality
- ✅ Multi-platform support
- ✅ Background downloads
- ✅ FFmpeg integration
- ✅ Metadata embedding
- ✅ Modern SwiftUI interface
- ✅ SoundCloud OAuth support
- ✅ URL scheme support
- 🔄 Continuous improvements
- 🔄 Additional platform support (via yt-dlp updates)

---

## ⚠️ Final Disclaimer

**This app is for educational and personal use only.**

- Respect content creators' rights
- Follow platform terms of service
- Downloading copyrighted content may violate terms of service and local laws
- Use responsibly and at your own risk
- The developers are not responsible for misuse of this software

**Not App Store Safe**: This app will likely be rejected by the App Store. Use side-loading methods for installation.

---

<div align="center">

**Made with ❤️ for the iOS community**

*If you find this project useful, please consider giving it a ⭐ on GitHub*

</div>
