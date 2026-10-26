#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  sddm-babu-theme  ·  uninstall.sh
#  Removes the theme and restores the OS default SDDM setup.
#  Run as your normal user (not root).  Uses sudo internally.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

THEME_NAME="sddm-babu-theme"
DEST="/usr/share/sddm/themes/$THEME_NAME"
FONT_DIR="/usr/share/fonts/$THEME_NAME"
SDDM_CONF="/etc/sddm.conf"
VIRTUALKBD_CONF="/etc/sddm.conf.d/virtualkbd.conf"
VIDEO_CONF="/etc/sddm.conf.d/10-babu-video.conf"

# ── helpers ───────────────────────────────────────────────────
info()  { printf '\033[1;32m  ✔  %s\033[0m\n' "$*"; }
warn()  { printf '\033[1;33m  ⚠  %s\033[0m\n' "$*" >&2; }
fatal() { printf '\033[1;31m  ✘  %s\033[0m\n' "$*" >&2; exit 1; }
hr()    { printf '\033[2m%s\033[0m\n' "────────────────────────────────────────────"; }

hr
printf '\033[1;31m  sddm-babu-theme  ·  Uninstaller\033[0m\n'
hr

# ── preflight ─────────────────────────────────────────────────
[[ "$EUID" -eq 0 ]] && fatal "Do not run as root. Run:  bash uninstall.sh"

if ! command -v sudo >/dev/null 2>&1; then
    fatal "sudo is not installed. Install and configure sudo first."
fi

if ! sudo -v 2>/dev/null; then
    fatal "sudo auth failed. Run:  sudo -v   then rerun uninstall.sh"
fi

info "Preflight passed"

# ── confirmation ──────────────────────────────────────────────
hr
printf '\n'
printf '  This will:\n'
printf '    1. Remove theme files from %s\n' "$DEST"
printf '    2. Remove the ArcadeClassic font from %s\n' "$FONT_DIR"
printf '    3. Remove drop-in configs (%s, %s)\n' "$VIRTUALKBD_CONF" "$VIDEO_CONF"
printf '    4. Restore SDDM to OS default theme\n'
printf '\n'

read -rp $'  Are you sure you want to uninstall? [y/N]: ' CONFIRM
case "$CONFIRM" in
    [yY]|[yY][eE][sS]) ;;
    *) info "Uninstall cancelled."; exit 0 ;;
esac

hr

# ── remove theme files ────────────────────────────────────────
if sudo test -d "$DEST"; then
    sudo rm -rf -- "$DEST"
    info "Removed theme directory → $DEST"
else
    warn "Theme directory not found ($DEST) — skipping"
fi

# ── remove font ───────────────────────────────────────────────
if sudo test -d "$FONT_DIR"; then
    sudo rm -rf -- "$FONT_DIR"
    sudo fc-cache -f 2>/dev/null || true
    info "Removed font directory → $FONT_DIR"
    info "Font cache refreshed"
else
    warn "Font directory not found ($FONT_DIR) — skipping"
fi

# ── remove drop-in configs ────────────────────────────────────
if sudo test -f "$VIRTUALKBD_CONF"; then
    sudo rm -f -- "$VIRTUALKBD_CONF"
    info "Removed virtual keyboard config → $VIRTUALKBD_CONF"
else
    warn "Virtual keyboard config not found — skipping"
fi

if sudo test -f "$VIDEO_CONF"; then
    sudo rm -f -- "$VIDEO_CONF"
    info "Removed video decoder config → $VIDEO_CONF"
else
    warn "Video decoder config not found — skipping"
fi

# ── restore sddm.conf ────────────────────────────────────────
#
# Strategy:
#   1. Look for installer backup (sddm.conf.bak.<timestamp>).
#      If found, restore the latest one.
#   2. If no backup exists, check if sddm.conf references our theme.
#      If yes, remove the Current= line (or the entire [Theme] section
#      if that's all it contains), which reverts SDDM to its built-in
#      default (usually "breeze" or "elarun" depending on distro).
#   3. If sddm.conf doesn't reference our theme, leave it alone.
#
hr
printf '\033[1;36m  Restoring SDDM configuration …\033[0m\n'
hr

RESTORED=false

# Try to find and restore the latest backup
if sudo test -f "$SDDM_CONF"; then
    LATEST_BACKUP=""
    for bak in "${SDDM_CONF}.bak."*; do
        if sudo test -f "$bak" 2>/dev/null; then
            # Only consider backups that do NOT point to our theme
            if ! sudo grep -q "Current=$THEME_NAME" "$bak" 2>/dev/null; then
                LATEST_BACKUP="$bak"
            fi
        fi
    done

    if [[ -n "$LATEST_BACKUP" ]]; then
        sudo cp -a -- "$LATEST_BACKUP" "$SDDM_CONF"
        info "Restored SDDM config from backup → $LATEST_BACKUP"
        RESTORED=true
    fi
fi

if [[ "$RESTORED" == false ]] && sudo test -f "$SDDM_CONF"; then
    # Check if our theme is referenced
    if sudo grep -q "Current=$THEME_NAME" "$SDDM_CONF" 2>/dev/null; then
        # Detect the OS default SDDM theme
        DEFAULT_THEME=""

        # Check for distro-specific defaults
        if [[ -f /etc/os-release ]]; then
            source /etc/os-release
            case "${ID:-}" in
                arch|endeavouros|manjaro|cachyos|garuda)
                    # Arch-based: SDDM ships with no default theme set → let SDDM pick its own
                    DEFAULT_THEME=""
                    ;;
                fedora|nobara)
                    # Fedora ships with "01-breeze-fedora" theme
                    if [[ -d "/usr/share/sddm/themes/01-breeze-fedora" ]]; then
                        DEFAULT_THEME="01-breeze-fedora"
                    elif [[ -d "/usr/share/sddm/themes/breeze" ]]; then
                        DEFAULT_THEME="breeze"
                    fi
                    ;;
                ubuntu|debian|linuxmint|pop)
                    # Debian/Ubuntu uses "debian-theme" or "breeze"
                    if [[ -d "/usr/share/sddm/themes/debian-theme" ]]; then
                        DEFAULT_THEME="debian-theme"
                    elif [[ -d "/usr/share/sddm/themes/breeze" ]]; then
                        DEFAULT_THEME="breeze"
                    fi
                    ;;
                opensuse*|suse*)
                    if [[ -d "/usr/share/sddm/themes/breeze" ]]; then
                        DEFAULT_THEME="breeze"
                    fi
                    ;;
                void)
                    DEFAULT_THEME=""
                    ;;
            esac
        fi

        # Remove our theme entry from sddm.conf using awk
        TMPCONF=$(mktemp)
        sudo cat "$SDDM_CONF" > "$TMPCONF"

        if [[ -n "$DEFAULT_THEME" ]]; then
            # Replace our theme with the OS default
            awk -v theme="$DEFAULT_THEME" '
                /^[[:space:]]*Current=sddm-babu-theme/ {
                    print "Current=" theme
                    next
                }
                { print }
            ' "$TMPCONF" | sudo tee "$SDDM_CONF" >/dev/null
            info "Replaced theme with OS default → $DEFAULT_THEME"
        else
            # Remove the Current= line entirely to let SDDM use its built-in default
            awk '
                BEGIN { in_theme=0; theme_has_content=0 }
                /^\[Theme\]/ { in_theme=1; next }
                /^\[/ { 
                    if (in_theme && theme_has_content) print "[Theme]"
                    in_theme=0
                }
                in_theme && /^[[:space:]]*Current=sddm-babu-theme/ { next }
                in_theme && /^[[:space:]]*[^[:space:]=]+=/ { theme_has_content=1 }
                !in_theme { print }
                in_theme && !/^[[:space:]]*Current=sddm-babu-theme/ { print }
            ' "$TMPCONF" | sudo tee "$SDDM_CONF" >/dev/null
            info "Removed theme setting — SDDM will use its built-in default"
        fi

        rm -f "$TMPCONF"

        # If sddm.conf is now empty (only whitespace), remove it entirely
        if [[ -z "$(sudo cat "$SDDM_CONF" | tr -d '[:space:]')" ]]; then
            sudo rm -f "$SDDM_CONF"
            info "Removed empty sddm.conf"
        fi
    else
        info "sddm.conf does not reference $THEME_NAME — left unchanged"
    fi
elif [[ "$RESTORED" == false ]]; then
    info "No sddm.conf found — SDDM will use its built-in default"
fi

# ── clean up backup files (optional) ─────────────────────────
BACKUP_COUNT=0
for bak in "${SDDM_CONF}.bak."*; do
    sudo test -f "$bak" 2>/dev/null && (( BACKUP_COUNT++ )) || true
done

if (( BACKUP_COUNT > 0 )); then
    printf '\n'
    read -rp "  Found $BACKUP_COUNT sddm.conf backup(s). Remove them? [y/N]: " CLEAN_BACKUPS
    case "$CLEAN_BACKUPS" in
        [yY]|[yY][eE][sS])
            for bak in "${SDDM_CONF}.bak."*; do
                if sudo test -f "$bak" 2>/dev/null; then
                    sudo rm -f -- "$bak"
                fi
            done
            info "Removed all sddm.conf backups"
            ;;
        *)
            info "Keeping backup files"
            ;;
    esac
fi

# ── clean up empty conf.d directory ──────────────────────────
if sudo test -d /etc/sddm.conf.d; then
    if [[ -z "$(sudo ls -A /etc/sddm.conf.d 2>/dev/null)" ]]; then
        sudo rmdir /etc/sddm.conf.d 2>/dev/null || true
        info "Removed empty /etc/sddm.conf.d directory"
    fi
fi

# ── SELinux relabeling (if present) ──────────────────────────
if command -v restorecon >/dev/null 2>&1; then
    if [[ -f "$SDDM_CONF" ]]; then
        sudo restorecon -F "$SDDM_CONF" >/dev/null 2>&1 || true
    fi
    if [[ -d /etc/sddm.conf.d ]]; then
        sudo restorecon -RF /etc/sddm.conf.d >/dev/null 2>&1 || true
    fi
    info "SELinux contexts restored"
fi

# ── summary ───────────────────────────────────────────────────
hr
info "Uninstallation complete!"
hr
printf '\n'
printf '  Removed:\n'
printf '    • Theme files       →  %s\n'  "$DEST"
printf '    • Fonts             →  %s\n'  "$FONT_DIR"
printf '    • VirtualKbd conf  →  %s\n'  "$VIRTUALKBD_CONF"
printf '    • Video decoder     →  %s\n'  "$VIDEO_CONF"
printf '\n'
printf '  SDDM will now use the OS default theme at next login.\n'
printf '\n'
printf '\033[1m  Reboot to apply changes.\033[0m\n'
printf '\n'
