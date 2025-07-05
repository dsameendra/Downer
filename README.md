# Downer — Video Downloader for macOS

**Downer** is a lightweight, native macOS app that lets you download your videos or audio from YT and more with just a few clicks. It lives in your **menubar** for quick access and also offers a full-featured main window.

## ✨ Features

- Download **video + audio**, **audio-only**, or **video-only**
- Choose from popular **resolutions** and **formats**
- Pick your **destination folder**
- Settings are **persisted** and shared between the main app and the menubar popover
- Minimal and clean **native macOS UI** with red-accent styling and dark mode support

<table align="center" style="border: none; border-collapse: collapse;">
<!--   <thead>
    <tr>
      <th align="center" style="padding: 8px; border: none;">App</th>
      <th align="center" style="padding: 8px; border: none;">Menubar Popover</th>
    </tr>
  </thead> -->
  <tbody>
    <tr>
	<td align="center" valign="top" style="border: none;">
		Darkmode
		<br>
		<img src="https://imgur.com/HJsr9dk.png" alt="Downer App Screenshot" width="300"/>
	</td>
	<td align="center" valign="top" style="border: none;">
		Lightmode
		<br>
        	<img src="https://imgur.com/13WYeoy.png" alt="Downer App Lightmode Screenshot" width="300"/>
     	</td>
   </tr>
   <tr>
       	<td align="center" valign="top" style="border: none;">
		Menubar App
		<br>
        	<img src="https://imgur.com/DqHR9HI.png" alt="Downer Menubar Screenshot" width="300"/>
      	</td>
      	<td align="center" valign="top" style="border: none;">
		Settings
		<br>
        	<img src="https://imgur.com/NTuM6in.png" alt="Downer Settings Screenshot" width="300"/>
      </td>
   </tr>
  </tbody>
</table>

## 🚀 Usage

1. Launch **Downer.app**  
2. Paste a YouTube URL  
3. Choose download type, resolution, format, etc.  
4. Press **Download**  
5. Watch status updates in real time  
6. Right-click the **menu bar icon** to open or quit the app

All preferences are remembered across launches.

## 💽 Installation Guide

### 1. Download and Install the App

Head over to the [GitHub Releases](https://github.com/dsameendra/Downer/releases) page and download the latest `.dmg` file.

- Open the `.dmg` and drag `Downer.app` into your `/Applications` folder.
- Make sure `yt-dlp` and `ffmpeg` is installed. If not install with `brew install yt-dlp ffmpeg`. 

---

### 2. Allow the App to Run

macOS might block the app from launching, saying:

> “Downer.app can’t be opened.”

This happens because the app is not signed with a paid Apple Developer account. But you can manually allow it using Terminal. Follow the instructions below.

1. Sign the app locally with an ad-hoc signature
```bash
codesign --force --deep --sign - /Applications/Downer.app
```

2. Remove the quarantine flag so macOS treats it as safe
```bash
xattr -dr com.apple.quarantine /Applications/Downer.app
```

## 🔧 Building from Source

### Requirements

- macOS 14+
- Xcode
- `yt-dlp`, `ffmpeg`, and `ffprobe` installed anywhere on disk  
  - Homebrew: `brew install yt-dlp ffmpeg`  
  - Or downloadable static binaries

### Steps

1. **Clone the repository**

   ```bash
   git clone https://github.com/dsameendra/Downer.git
   cd Downer
   ``` 
2. Open `Downer.xcodeproj` in Xcode
3. Set your personal signing team
	1.	In the Project navigator, click Downer (the blue project icon).
	2.	Select the Downer TARGET → Signing & Capabilities tab.
	3.	From the Team dropdown choose your Apple‑ID team (or add one).
Automatic signing is sufficient for local builds—Xcode will generate a
debug profile and sign the bundle.
4. Install the yt-dlp and ffmpeg command‑line dependencies (skip if you already have them).
5. Build and run.
7. First‑run setup
	1.	Go to Settings → Tool Paths.
	2.  Verify the paths to yt-dlp, ffmpeg, and ffprobe (Homebrew defaults should be auto‑detected).
	3.  Choose a global shortcut if you like.

## 📦 Installing Locally
If you're building the app yourself via Xcode, you can export and install it manually like this:
1. In **Xcode**, go to `Product` → `Archive`
2. Once the archive is complete, Xcode will open the **Organizer** window
3. Click **Distribute App** → choose **Custom** → then **Copy App**
4. Save the exported `.app` file to your desired location on disk
5. Copy the `Downer.app` to your `/Applications` folder

---

## ⚠️ Disclaimer

This tool is intended solely for personal use and educational or research purposes.

Downloading videos from YouTube may violate their [Terms of Service](https://www.youtube.com/t/terms) unless the video has an explicit download button or the content is licensed in a way that permits downloading.

By using this app, **you assume full responsibility** for any content you download and how you use it. The developer does not condone or support any misuse of this tool to infringe upon copyrights or violate platform rules.

---

Built with ❤️ using [yt-dlp](https://github.com/yt-dlp/yt-dlp) and [ffmpeg](https://www.ffmpeg.org). Huge credit to the amazing developers behind these tools.
