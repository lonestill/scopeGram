<div align="center">
  <img src="Telegram-Mac/Assets.xcassets/AppIcon.appiconset/Logo_1024.png" width="120" height="120" alt="Scopegram Logo">
  <h1>Scopegram for macOS</h1>
  <p><strong>A fully native, feature-complete, and private Telegram client for macOS.</strong></p>

  <p>
    <a href="https://github.com/lonestill/scopeGram/releases"><img src="https://img.shields.io/github/v/release/lonestill/scopeGram?style=flat-square&color=007AFF" alt="Latest Release"></a>
    <img src="https://img.shields.io/badge/platform-macOS%2012.0%2B-blue?style=flat-square" alt="Platform macOS">
    <img src="https://img.shields.io/badge/architecture-Apple%20Silicon%20(arm64)-success?style=flat-square" alt="Architecture arm64">
    <img src="https://img.shields.io/badge/swift-5.9%2B-orange?style=flat-square" alt="Swift">
    <img src="https://img.shields.io/badge/license-GPL--2.0-lightgrey?style=flat-square" alt="License GPL-2.0">
    <img src="https://img.shields.io/badge/injection-zero%20(100%25%20native)-green?style=flat-square" alt="Zero Injection">
  </p>
</div>

---

## ⚡ Overview

**Scopegram** is a power-user Telegram client for macOS compiled directly from source. It unlocks complete freedom and privacy controls without compromising the buttery-smooth performance of the native Swift interface.

Unlike generic injected dylib solutions or Electron wrappers, **Scopegram is 100% native Swift & Objective-C++**: zero runtime hook injection, zero Frida overhead, zero memory instability, and full compatibility with macOS Sonoma & Sequoia.

---

## 🚀 Key Features

### ⏱ Unlocked View-Once & Self-Destructing Media
- **Direct Desktop Playback**: View-once photos and expiring videos render natively inside the desktop chat without showing the *"View on mobile device"* restriction placeholder.
- **Permanent Availability**: Media does not burn or disappear after opening. Open and inspect self-destructing media anytime in full resolution.
- **Copy & Save Protection Bypass**: Full keyboard shortcuts (`Cmd+C`), right-click menu, and gallery save buttons unlocked for secret/ephemeral media.
- **No View Receipts**: Sender never receives a view receipt or timer trigger.

### 🗑 Anti-Delete Message Protection
- **Deleted Messages Retention**: Messages deleted by other participants stay visible in your chat log.
- **Visual Badge**: Deleted messages display a clean, distinct red `🗑 deleted` indicator next to their timestamp.
- **Session Persistence**: Deleted message registries persist across application restarts.

### 📝 Message Edit History
- **Revision Counter**: Edited messages display an edit counter badge on the bubble (e.g. `изменено (1)`, `изменено (2)`).
- **History Inspector**: Right-click any edited message and select **История изменений** (Edit History) to view timestamped historical versions alongside the current text.

### 👻 Ghost Mode & Stealth Privacy
- **Don't Send Read Receipts**: Read incoming messages silently without marking them as read for the sender.
- **Stealth Story Viewing**: Watch stories anonymously without your profile appearing in the viewer list.
- **Typing Status Control**: Suppress typing indicators while composing messages.

### 🔓 Channel & Content Restrictions Bypass
- **Anti-Noforwards**: Copy text, save media, and forward messages freely even from protected channels and private groups with saving restrictions enabled.
- **No Screen Recording Blockers**: Full window capture and screenshot freedom.

### 🛡 Identity & UI Polishing
- **AdBlock**: All Telegram sponsored messages and channel promotional banners are hidden.
- **Accidental Call Protection**: Confirmation alert before initiating voice or video calls.
- **Peer ID Display**: Numeric Peer ID displayed directly in user and group profiles with one-click copy to clipboard.
- **Phone Number Masking**: Mask phone numbers as `+* *** ***-**-**` in user info and settings for screen-sharing and streaming privacy.
- **Dedicated Settings Hub**: Comprehensive toggle interface under `Settings -> Scopegram Settings`.

### 🔄 Native GitHub Releases Updater
- **No Vanilla Telegram Overwrite**: All connections to Telegram's official update servers and Sparkle feeds are decoupled to protect your custom build from being overwritten.
- **Direct GitHub Updates**: Automatically checks `lonestill/scopeGram` releases via GitHub REST API.
- **In-App Download**: Realtime progress indicator (`Downloading X MB / Y MB`) and 1-click DMG mounting on completion.

---

## 📦 Installation

1. Download the latest **`Scopegram-macos-arm64.dmg`** from [Releases](https://github.com/lonestill/scopeGram/releases).
2. Open the DMG image and drag **Scopegram.app** to your `/Applications` directory.
3. Because Scopegram is an independent open-source release built with ad-hoc signing, macOS Gatekeeper may display a security notification on the first launch. If prompted, run this command in Terminal to clear the quarantine attribute:
   ```bash
   xattr -cr /Applications/Scopegram.app
   ```
4. Launch **Scopegram** and log in!

---

## 🛠 Building from Source

### Prerequisites
- macOS 12.0+ (Apple Silicon arm64 recommended).
- Xcode 15 or newer with Command Line Tools.
- Homebrew & Python 3.

### Option 1: Fast Build (~3–5 minutes)
Bypass compiling 12 heavy C++/Rust core frameworks (FFmpeg, WebRTC, OpenSSL, libvpx, dav1d, etc.) by restoring precompiled binaries:

```bash
# 1. Clone repository with all submodules
git clone --recurse-submodules https://github.com/lonestill/scopeGram.git
cd scopeGram

# 2. Download and unpack precompiled core frameworks
sh scripts/download_precompiled.sh

# 3. Build native Scopegram bundle
python3 build_scopegram.py
```

### Option 2: Full Build from Scratch (~30–45 minutes)

```bash
# 1. Install build tools
brew install cmake ninja meson nasm yasm openssl@3 zlib autoconf libtool automake pkg-config

# 2. Setup build environment and compile all submodules
sh scripts/setup_build_env.sh --build

# 3. Compile and launch Scopegram
python3 build_scopegram.py --run
```

---

## 🏗 Architecture

Scopegram is organized into a modular Swift Package Manager (SPM) architecture:
- `Telegram-Mac/`: App lifecycle, menu hooks, window orchestration, and native update manager (`ScopegramUpdateManager`).
- `packages/`: Over 90 modular Swift packages (`ChatUI`, `GalleryUI`, `SettingsUI`, `PeerInfoUI`, `MessageUtils`, `TGUIKit`).
- `submodules/telegram-ios/`: Core network layers, MTProto engine, and state machine (`TelegramCore`, `Postbox`, `SSignalKit`).
- `core-xprojects/`: Hardware-accelerated media decoders and telephony engines (FFmpeg, WebRTC/tg_owt, Opus, OpenH264).

---

## ⚖️ License & Disclaimer

- Scopegram is licensed under the **GNU General Public License v2.0** ([LICENSE](LICENSE)).
- This project is an independent fork of the open-source Telegram for macOS client. It is not affiliated with, endorsed by, or sponsored by Telegram FZ-LLC. All product names, logos, and brands are property of their respective owners.
