# Downer — YouTube Downloader for macOS

**Downer** is a lightweight, native macOS app that lets you download YouTube videos or audio with just a few clicks. It lives in your **menubar** for quick access and also offers a full-featured main window.

## ✨ Features

- Download **video + audio**, **audio-only**, or **video-only**
- Choose from popular **resolutions** and **formats**
- Pick your **destination folder**
- Settings are **persisted** and shared between the main app and the menubar popover
- Minimal and clean **native macOS UI** with red-accent styling and dark mode support

<table align="center" style="border: none; border-collapse: collapse;">
  <thead>
    <tr>
      <th align="center" style="padding: 8px; border: none;">App</th>
      <th align="center" style="padding: 8px; border: none;">Menubar Popover</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td align="center" valign="top" style="border: none;">
        <img src="https://imgur.com/Ge4BPPo.png" alt="Downer App Screenshot" width="400"/>
      </td>
      <td align="center" valign="top" style="border: none;">
        <img src="https://imgur.com/nDnaa7s.png" alt="Downer Menubar Screenshot" width="400"/>
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

Built with ❤️ using [yt-dlp](https://github.com/yt-dlp/yt-dlp) and [ffmpeg](https://www.ffmpeg.org). Huge credit to the amazing developers behind these tools.
