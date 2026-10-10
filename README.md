<div align="center">

# 🌸 sddm-babu-theme

**A pixel-sakura style SDDM login theme with a custom video background.**  
Silent looping video · ArcadeClassic font · Fully opaque input fields · Qt6

![Theme Style](https://img.shields.io/badge/style-pixel__sakura-ff8fab?style=flat-square)
![Qt Version](https://img.shields.io/badge/Qt-%3E%3D6.8-41CD52?style=flat-square&logo=qt)
![SDDM Version](https://img.shields.io/badge/SDDM-%3E%3D0.21-5c7cfa?style=flat-square)
![License](https://img.shields.io/badge/license-GPL--3.0--or--later-blue?style=flat-square)

</div>

---

## ✨ Features

- 🎬 **Looping video background** — `BABU.mp4`, no audio, plays silently at login
- 🕐 **Live clock** — large `HH:mm` time + `dddd d` date in ArcadeClassic font
- 🔲 **Opaque input fields** — solid `#cccccc` username and password bars
- 🎨 **pixel_sakura color palette** — muted navy `#3d495b` on light gray
- ⌨️ **Login with Enter** — no login button shown; just type password and press Enter
- 🔇 **No audio** — the background video has its audio track stripped

---

## 📋 Requirements

| Requirement | Minimum version |
|---|---|
| [SDDM](https://github.com/sddm/sddm) | `>= 0.21` |
| Qt | `>= 6.8` |
| Qt Multimedia (FFmpeg backend) | installed |
| Qt Virtual Keyboard | installed |

### Install requirements by distro

**Arch Linux**
```bash
sudo pacman -S --needed sddm qt6-svg qt6-virtualkeyboard qt6-multimedia-ffmpeg ffmpeg fontconfig
```

**Debian / Ubuntu**
```bash
sudo apt install sddm qt6-svg-dev qml6-module-qtquick-virtualkeyboard \
  qt6-multimedia-dev qml6-module-qtquick-controls qml6-module-qtquick-effects \
  qml6-module-qtmultimedia ffmpeg fontconfig libxcb-cursor0
```

**Fedora**
```bash
sudo dnf install sddm qt6-qtsvg qt6-qtvirtualkeyboard qt6-qtmultimedia ffmpeg-free fontconfig
```

**openSUSE**
```bash
sudo zypper install sddm-qt6 libQt6Svg6 qt6-virtualkeyboard qt6-virtualkeyboard-imports \
  qt6-multimedia qt6-multimedia-imports ffmpeg fontconfig
```

---

## 🚀 Install — one command

```bash
bash install.sh
```

That's it. The script will:

1. Copy the theme to `/usr/share/sddm/themes/sddm-babu-theme/`
2. Install the **ArcadeClassic** font system-wide
3. Set `Current=sddm-babu-theme` in `/etc/sddm.conf` (backs up the old config first)
4. Write `/etc/sddm.conf.d/virtualkbd.conf` for the virtual keyboard
5. Enable SDDM for the next boot (without starting or restarting anything now)

> **Note:** Do **not** run as root. The script uses `sudo` internally and will ask for your password once.

After the script finishes, **reboot** to see your new login screen.

---

## 👁️ Preview without rebooting

If you have a graphical session open, you can preview the theme instantly:

```bash
sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/sddm-babu-theme/
```

---

## 🔙 Uninstall / Rollback

**Restore your previous SDDM theme:**
```bash
# The installer prints the backup path — use it here:
sudo cp /etc/sddm.conf.bak.<timestamp> /etc/sddm.conf
```

**Remove the theme files:**
```bash
sudo rm -rf /usr/share/sddm/themes/sddm-babu-theme
sudo rm -rf /usr/share/fonts/sddm-babu-theme
sudo fc-cache -f
```

---

## 📁 Theme structure

```
sddm-babu-theme/
├── Assets/               SVG icons (shutdown, reboot, suspend …)
├── Backgrounds/
│   └── BABU.mp4          Silent H.264/yuv420p video background
├── Components/           QML components (clock, input, session …)
├── Fonts/
│   └── ARCADECLASSIC.TTF Pixel/arcade display font
├── Themes/
│   └── babu.conf         Theme configuration (pixel_sakura palette)
├── Main.qml              Main QML entry point
├── metadata.desktop      SDDM theme descriptor
├── install.sh            ← run this to install
├── NOTICE.txt            GPL attribution
└── LICENSE               GPL-3.0-or-later
```

---

## ⚙️ Customisation

All options live in [`Themes/babu.conf`](Themes/babu.conf). Key settings:

```ini
Font="arcadeclassic"          # display font
HourFormat="HH:mm"            # clock format (24h)
DateFormat="dddd d"           # date format

Background="Backgrounds/BABU.mp4"   # video path (must be lowercase .mp4)

LoginFieldBackgroundColor="#cccccc"   # input box colour
PasswordFieldBackgroundColor="#cccccc"
TimeTextColor="#3d495b"
DateTextColor="#3d495b"

FormPosition="center"         # center | left | right
HideLoginButton="true"        # login with Enter key
```

---

## 🛠️ Troubleshooting

| Problem | Fix |
|---|---|
| **Black / dark background, no video** | Check that `qt6-multimedia` with the FFmpeg backend is installed. On Fedora: `libavcodec-freeworld` from RPM Fusion. |
| **Video not playing** | Confirm the file is named exactly `BABU.mp4` (lowercase `.mp4`) in `Backgrounds/`. |
| **Font not applied** | Run `sudo fc-cache -f` then `fc-list \| grep -i arcade`. |
| **Theme overridden at boot** | Check for `Current=` in `/etc/sddm.conf.d/*.conf` or `/usr/lib/sddm/sddm.conf.d/*.conf`. |
| **Login screen not showing after reboot** | Make sure SDDM is enabled: `sudo systemctl enable --force sddm.service`. |
| **Video stutters** | Re-encode at a lower bitrate or frame rate with ffmpeg before replacing `Backgrounds/BABU.mp4`. |

---

## 📜 Credits & License

Based on **[sddm-astronaut-theme](https://github.com/Keyitdev/sddm-astronaut-theme)** by [Keyitdev](https://github.com/Keyitdev).  
Distributed under the [GPL-3.0-or-later](LICENSE) License.

Modifications: pixel_sakura variant with a custom video background and fully opaque input fields.
