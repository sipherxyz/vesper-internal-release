# Vesper

An AI agent desktop platform built on the Claude Agent SDK.

Download the latest version from the **[Releases](https://github.com/sipherxyz/vesper-internal-release/releases)** page.

---

## Download

| Platform | File | Architecture |
|----------|------|-------------|
| macOS (Apple Silicon) | `Vesper-arm64.dmg` | M1 / M2 / M3 / M4 |
| macOS (Intel) | `Vesper-x64.dmg` | Intel x86_64 |
| Windows | `Vesper-x64.exe` | 64-bit |
| Linux | `Vesper-x86_64.AppImage` | 64-bit |

Go to the [Releases](https://github.com/sipherxyz/vesper-internal-release/releases) page and download the file matching your platform.

---

## Installation

### macOS

1. Download `Vesper-arm64.dmg` (Apple Silicon) or `Vesper-x64.dmg` (Intel)
2. Open the `.dmg` file
3. Drag **Vesper** to the **Applications** folder
4. Eject the disk image
5. Open Vesper from Applications

**First launch - Gatekeeper warning:**

macOS may show _"Vesper can't be opened because Apple cannot check it for malicious software."_ To fix this:

- **Option A (GUI):** Go to **System Settings > Privacy & Security**, scroll down to the Security section, and click **Open Anyway** next to the Vesper message.
- **Option B (Terminal):** Run this command to remove the quarantine attribute:
  ```bash
  xattr -rd com.apple.quarantine /Applications/Vesper.app
  ```

Then open Vesper again normally.

### Windows

1. Download `Vesper-x64.exe`
2. Run the installer and follow the prompts
3. Vesper will be installed to `%LOCALAPPDATA%\Programs\Vesper\`
4. Launch from the Start Menu or desktop shortcut

**SmartScreen warning:**

Windows may show _"Windows protected your PC"_. Click **More info**, then click **Run anyway**.

### Linux

1. Download `Vesper-x86_64.AppImage`
2. Make it executable and run:
   ```bash
   chmod +x Vesper-x86_64.AppImage
   ./Vesper-x86_64.AppImage
   ```

**Optional - install to PATH:**

```bash
# Move to a permanent location
mkdir -p ~/.local/bin
mv Vesper-x86_64.AppImage ~/.local/bin/vesper
chmod +x ~/.local/bin/vesper

# Ensure ~/.local/bin is in your PATH
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Launch
vesper
```

**Dependencies:**

AppImage requires FUSE to run. Install if not already present:

```bash
# Debian / Ubuntu
sudo apt install fuse libfuse2

# Fedora
sudo dnf install fuse fuse-libs
```

---

## Updating

When a new version is released, download the latest installer from the [Releases](https://github.com/sipherxyz/vesper-internal-release/releases) page and install it over the existing version. Your settings and data in `~/.vesper/` are preserved across updates.

---

## System Requirements

| | Minimum |
|---|---|
| **macOS** | macOS 12 (Monterey) or later |
| **Windows** | Windows 10 (64-bit) or later |
| **Linux** | Ubuntu 20.04+ / Fedora 36+ or equivalent (x86_64, FUSE required) |
| **RAM** | 8 GB recommended |
| **Disk** | ~500 MB for the application |

---

## Configuration

All user data is stored in `~/.vesper/` (macOS/Linux) or `%USERPROFILE%\.vesper\` (Windows):

```
~/.vesper/
├── config.json          # Main configuration
├── credentials.enc      # Encrypted API keys
├── preferences.json     # User preferences
└── workspaces/          # Sessions, memory, and workspace data
```

On first launch, Vesper will prompt you to configure your API key.

---

## Troubleshooting

**App won't open on macOS**
Remove the quarantine flag: `xattr -rd com.apple.quarantine /Applications/Vesper.app`

**"FUSE not found" on Linux**
Install FUSE: `sudo apt install fuse libfuse2` (Ubuntu) or `sudo dnf install fuse fuse-libs` (Fedora)

**Windows installer blocked by antivirus**
Add an exception for `Vesper-x64.exe` in your antivirus software, or temporarily disable real-time protection during installation.

**App crashes on launch**
Try deleting the cache and restarting:
- macOS: `rm -rf ~/Library/Application\ Support/Vesper/Cache`
- Linux: `rm -rf ~/.config/@vesper`
- Windows: Delete `%APPDATA%\Vesper\Cache`
