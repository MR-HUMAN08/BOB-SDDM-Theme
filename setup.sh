#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  sddm-babu-theme  ·  setup.sh
#  Automatic installer — run with:
#    bash -c "$(curl -fsSL https://raw.githubusercontent.com/MR-HUMAN08/BOB-SDDM-Theme/main/setup.sh)"
#
#  Works on: Arch, Fedora, Debian/Ubuntu, openSUSE, Void
#  Run as your normal user (not root).  Uses sudo internally.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

readonly THEME_REPO="https://github.com/MR-HUMAN08/BOB-SDDM-Theme.git"
readonly THEME_NAME="sddm-babu-theme"
readonly THEMES_DIR="/usr/share/sddm/themes"
readonly CLONE_DIR="$HOME/BOB-SDDM-Theme"
readonly DATE=$(date +%s)

# ── helpers ───────────────────────────────────────────────────
info()  { printf '\033[1;32m  ✔  %s\033[0m\n' "$*"; }
warn()  { printf '\033[1;33m  ⚠  %s\033[0m\n' "$*" >&2; }
fatal() { printf '\033[1;31m  ✘  %s\033[0m\n' "$*" >&2; exit 1; }
hr()    { printf '\033[2m%s\033[0m\n' "────────────────────────────────────────────"; }

# ── banner ────────────────────────────────────────────────────
clear 2>/dev/null || true
hr
printf '\033[1;36m  🎬 sddm-babu-theme  ·  Automatic Setup\033[0m\n'
printf '\033[2m  Pixel-sakura SDDM theme with video background\033[0m\n'
hr
printf '\n'

# ── preflight ─────────────────────────────────────────────────
[[ "$EUID" -eq 0 ]] && fatal "Do not run as root. Run without sudo."

if ! command -v sudo >/dev/null 2>&1; then
    fatal "sudo is not installed. Install and configure sudo first."
fi

if ! sudo -v 2>/dev/null; then
    fatal "sudo auth failed. Run:  sudo -v   then rerun."
fi

# ── detect package manager ────────────────────────────────────
detect_pkg_manager() {
    for mgr in pacman xbps-install dnf zypper apt; do
        if command -v "$mgr" >/dev/null 2>&1; then
            echo "$mgr"
            return
        fi
    done
    echo "unknown"
}

PKG_MGR=$(detect_pkg_manager)
info "Detected package manager: $PKG_MGR"

[[ "$PKG_MGR" == "unknown" ]] && fatal "Unsupported package manager. Supported: pacman, apt, dnf, zypper, xbps-install"

# ── install dependencies ──────────────────────────────────────
hr
printf '\033[1;36m  📦 Installing dependencies …\033[0m\n'
hr

case "$PKG_MGR" in
    pacman)
        sudo pacman -S --needed --noconfirm \
            sddm qt6-svg qt6-virtualkeyboard qt6-multimedia-ffmpeg \
            ffmpeg fontconfig git
        ;;
    apt)
        sudo apt update
        sudo apt install -y \
            sddm qt6-svg-dev qml6-module-qtquick-virtualkeyboard \
            qt6-multimedia-dev qml6-module-qtquick-controls qml6-module-qtquick-effects \
            qml6-module-qtmultimedia ffmpeg fontconfig libxcb-cursor0 git
        ;;
    dnf)
        # ffmpeg (RPMFusion) conflicts with ffmpeg-free (Fedora).
        # If the user already has ffmpeg, skip installing ffmpeg-free.
        FFMPEG_PKG="ffmpeg-free"
        if rpm -q ffmpeg &>/dev/null; then
            info "ffmpeg (RPMFusion) already installed — skipping ffmpeg-free"
            FFMPEG_PKG=""
        fi
        sudo dnf install -y \
            sddm qt6-qtsvg qt6-qtvirtualkeyboard qt6-qtmultimedia \
            $FFMPEG_PKG fontconfig git
        ;;
    zypper)
        sudo zypper install -y \
            sddm-qt6 libQt6Svg6 qt6-virtualkeyboard qt6-virtualkeyboard-imports \
            qt6-multimedia qt6-multimedia-imports ffmpeg fontconfig git
        ;;
    xbps-install)
        sudo xbps-install -Sy \
            sddm qt6-svg qt6-virtualkeyboard qt6-multimedia \
            ffmpeg fontconfig git
        ;;
esac

info "Dependencies installed"

# ── clone or update repository ────────────────────────────────
hr
printf '\033[1;36m  📥 Getting theme files …\033[0m\n'
hr

if [[ -d "$CLONE_DIR/.git" ]]; then
    info "Repository already exists → $CLONE_DIR"
    read -rp $'  Pull latest changes? [Y/n]: ' PULL_CHOICE
    case "$PULL_CHOICE" in
        [nN]|[nN][oO])
            info "Using existing files"
            ;;
        *)
            git -C "$CLONE_DIR" pull --ff-only || {
                warn "Pull failed — using existing files"
            }
            info "Repository updated"
            ;;
    esac
else
    if [[ -d "$CLONE_DIR" ]]; then
        warn "Non-git directory exists at $CLONE_DIR"
        read -rp $'  Remove and re-clone? [y/N]: ' RECLONE
        case "$RECLONE" in
            [yY]|[yY][eE][sS])
                rm -rf -- "$CLONE_DIR"
                ;;
            *)
                fatal "Cannot proceed — remove $CLONE_DIR manually and rerun."
                ;;
        esac
    fi
    git clone --depth 1 "$THEME_REPO" "$CLONE_DIR"
    info "Repository cloned → $CLONE_DIR"
fi

# ── verify install.sh exists ─────────────────────────────────
[[ ! -f "$CLONE_DIR/install.sh" ]] && fatal "install.sh not found in $CLONE_DIR — clone may be incomplete."

# ── run the theme installer ──────────────────────────────────
hr
printf '\033[1;36m  🚀 Running theme installer …\033[0m\n'
hr
printf '\n'

cd "$CLONE_DIR"
bash install.sh

# ── final summary ─────────────────────────────────────────────
hr
printf '\033[1;32m  🎉 Setup complete!\033[0m\n'
hr
printf '\n'
printf '  The theme has been installed and configured.\n'
printf '  \033[1mReboot to see your new login screen.\033[0m\n'
printf '\n'
printf '  ─── Quick reference ───\n'
printf '\n'
printf '  Preview:     sddm-greeter-qt6 --test-mode --theme %s/%s/\n' "$THEMES_DIR" "$THEME_NAME"
printf '  Uninstall:   bash %s/uninstall.sh\n' "$CLONE_DIR"
printf '  Reinstall:   bash %s/install.sh\n' "$CLONE_DIR"
printf '\n'
