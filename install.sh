#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  sddm-babu-theme  ·  install.sh
#  Run as your normal user (not root).  Uses sudo internally.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

# ── editable variables ────────────────────────────────────────
LOOP_TARGET_SECONDS=180   # target total video length in seconds (lower = smaller file)

THEME_NAME="sddm-babu-theme"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
printf '\033[1;36m  sddm-babu-theme  ·  Installer\033[0m\n'
hr

# ── preflight ─────────────────────────────────────────────────
[[ "$EUID" -eq 0 ]] && fatal "Do not run as root. Run:  bash install.sh"

[[ ! -f "$SCRIPT_DIR/Main.qml" ]] && \
    fatal "Run this script from inside the sddm-babu-theme folder."

[[ ! -f "$SCRIPT_DIR/Backgrounds/BABU.mp4" ]] && \
    fatal "Backgrounds/BABU.mp4 is missing from the theme folder."

if ! command -v sudo >/dev/null 2>&1; then
    fatal "sudo is not installed. Install and configure sudo first."
fi

if ! sudo -v 2>/dev/null; then
    fatal "sudo auth failed. Run:  sudo -v   then rerun install.sh"
fi

for tool in ffmpeg ffprobe awk; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        fatal "$tool is not installed. Install ffmpeg and rerun."
    fi
done

info "Preflight passed"

# ── video preparation ─────────────────────────────────────────
#
# Strategy:
#   1. Probe the source clip. If it is already clean H.264/yuv420p ≤1920×1080
#      we use it as the "clip" directly (no intermediate re-encode).
#      Otherwise we re-encode it to a clean intermediate first.
#   2. From the clip, build the final looped BABU.mp4 in one pass using
#      -stream_loop so that Qt MediaPlayer never has to seek back to 0.
#
TMPDIR_VIDEO=$(mktemp -d)
trap 'rm -rf -- "$TMPDIR_VIDEO"' EXIT

SRC="$SCRIPT_DIR/Backgrounds/BABU.mp4"
CLIP="$TMPDIR_VIDEO/clip.mp4"
FINAL="$TMPDIR_VIDEO/BABU.mp4"

info "Probing source video …"
CODEC=$(ffprobe -v error -select_streams v:0 \
    -show_entries stream=codec_name -of csv=p=0 "$SRC" 2>/dev/null | head -1 || true)
PIX=$(ffprobe -v error -select_streams v:0 \
    -show_entries stream=pix_fmt -of csv=p=0 "$SRC" 2>/dev/null | head -1 || true)
W=$(ffprobe -v error -select_streams v:0 \
    -show_entries stream=width -of csv=p=0 "$SRC" 2>/dev/null | head -1 || true)
H=$(ffprobe -v error -select_streams v:0 \
    -show_entries stream=height -of csv=p=0 "$SRC" 2>/dev/null | head -1 || true)

[[ -z "$CODEC" ]] && fatal "Cannot read video stream from $SRC — is it a valid video file?"

info "Source: codec=$CODEC pix_fmt=$PIX size=${W}x${H}"

if [[ "$CODEC" == "h264" && "$PIX" == "yuv420p" ]] \
    && [[ "$W" =~ ^[0-9]+$ && "$H" =~ ^[0-9]+$ ]] \
    && (( W <= 1920 && H <= 1080 )); then
    info "Source is already clean H.264/yuv420p — using as clip directly (stream copy)"
    ffmpeg -y -v error -i "$SRC" -an -c:v copy "$CLIP"
else
    info "Re-encoding source to clean H.264/yuv420p clip …"
    ffmpeg -y -v error -i "$SRC" -an \
        -vf "setpts=PTS-STARTPTS,scale=w='min(1920,iw)':h='min(1080,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2" \
        -fps_mode passthrough \
        -c:v libx264 -pix_fmt yuv420p -crf 23 -preset medium \
        -movflags +faststart "$CLIP"
fi

# Probe clip duration defensively
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$CLIP" 2>/dev/null | head -1 || true)
DUR="${DUR// /}"   # strip whitespace

if [[ -z "$DUR" || "$DUR" == "N/A" ]]; then
    fatal "Could not read duration from clip — ffprobe returned empty or N/A."
fi
# Verify it is a positive number
if ! awk -v d="$DUR" 'BEGIN{ if (d+0 <= 0) exit 1 }'; then
    fatal "Clip duration is zero or negative ($DUR s) — cannot build looped video."
fi

# Calculate number of stream_loop repetitions
N=$(awk -v d="$DUR" -v t="$LOOP_TARGET_SECONDS" \
    'BEGIN{ n=int(t/d); if(n<1) n=1; print n }')

PLAYS=$(( N + 1 ))
TOTAL_S=$(awk -v n="$PLAYS" -v d="$DUR" 'BEGIN{ printf "%.0f", n*d }')
info "Clip: ${DUR}s  ·  stream_loop=$N  ·  plays=${PLAYS} (N+1)  ·  total≈${TOTAL_S}s  ·  target=${LOOP_TARGET_SECONDS}s"
info "Building looped BABU.mp4 in one encode pass (this may take a few minutes) …"

ffmpeg -y -v error \
    -stream_loop "$N" -i "$CLIP" \
    -an \
    -vf "setpts=N/FRAME_RATE/TB" \
    -fps_mode passthrough \
    -c:v libx264 -pix_fmt yuv420p \
    -crf 23 -preset medium \
    -g 48 \
    -movflags +faststart \
    "$FINAL"

# Report file size and duration of final file
FINAL_SIZE_BYTES=$(stat -c%s "$FINAL")
FINAL_SIZE_MB=$(awk -v b="$FINAL_SIZE_BYTES" 'BEGIN{ printf "%.1f", b/1024/1024 }')
FINAL_DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$FINAL" 2>/dev/null | head -1 || true)
FINAL_DUR_INT=$(awk -v d="${FINAL_DUR:-0}" 'BEGIN{ printf "%d", d+0 }')

info "Final video: ${FINAL_SIZE_MB} MB  ·  duration: ${FINAL_DUR_INT}s"

if (( FINAL_SIZE_BYTES > 300 * 1024 * 1024 )); then
    warn "Final video exceeds 300 MB (${FINAL_SIZE_MB} MB). " \
         "Consider lowering LOOP_TARGET_SECONDS (currently ${LOOP_TARGET_SECONDS}) and rerunning."
fi

# Decode test — first 3 seconds
info "Running 3-second decode test …"
DECODE3_OUT=$(ffmpeg -v error -i "$FINAL" -t 3 -f null - 2>&1 || true)
if [[ -n "$DECODE3_OUT" ]]; then
    fatal "3-second decode test reported errors:\n${DECODE3_OUT}"
fi
info "3-second decode test passed"

# Full file decode test (proves no errors at loop joins)
info "Running full-file decode test (checks loop seams) …"
DECODE_FULL_OUT=$(ffmpeg -v error -i "$FINAL" -f null - 2>&1 || true)
if [[ -n "$DECODE_FULL_OUT" ]]; then
    fatal "Full-file decode test reported errors:\n${DECODE_FULL_OUT}"
fi
info "Full-file decode test passed — no errors at loop joins"

# NOTE: $SCRIPT_DIR/Backgrounds/BABU.mp4 (the original clip) is intentionally
# NOT overwritten here — it stays as the loop source for future re-runs.
# The looped video is copied into DEST after the theme files are installed.

# ── install theme files ───────────────────────────────────────
if sudo test -d "$DEST"; then
    if sudo grep -Fxq "Theme-Id=$THEME_NAME" "$DEST/metadata.desktop" 2>/dev/null; then
        info "Removing previous installation"
        sudo rm -rf -- "$DEST"
    else
        fatal "A different directory exists at $DEST. Remove it first."
    fi
fi

sudo install -d -m 755 "$DEST"
sudo cp -a -- "$SCRIPT_DIR"/. "$DEST"/
# remove installer and readme from the installed copy (not needed in /usr/share)
sudo rm -rf -- "$DEST/install.sh" "$DEST/README.md" "$DEST/test-logs"
sudo find "$DEST" -type d -exec chmod 755 {} +
sudo find "$DEST" -type f -exec chmod 644 {} +
# Replace BABU.mp4 in the installed copy with the looped version
# (source $SCRIPT_DIR/Backgrounds/BABU.mp4 is kept as the original clip)
sudo cp -- "$FINAL" "$DEST/Backgrounds/BABU.mp4"
sudo chmod 644 "$DEST/Backgrounds/BABU.mp4"
info "Theme files installed → $DEST"
info "Looped video installed → $DEST/Backgrounds/BABU.mp4  (${FINAL_SIZE_MB} MB, ${FINAL_DUR_INT}s)"

# ── install font ──────────────────────────────────────────────
sudo install -d -m 755 "$FONT_DIR"
sudo install -m 644 "$SCRIPT_DIR/Fonts/ARCADECLASSIC.TTF" \
    "$FONT_DIR/ARCADECLASSIC.TTF"
sudo fc-cache -f
if fc-list 2>/dev/null | grep -qi arcadeclassic; then
    info "ArcadeClassic font registered"
else
    warn "ArcadeClassic not found via fc-list — it may still work at login"
fi

# ── SELinux relabeling (if present) ──────────────────────────
if command -v restorecon >/dev/null 2>&1; then
    sudo restorecon -RF "$DEST" "$FONT_DIR" >/dev/null 2>&1 || true
    info "SELinux contexts restored"
fi

# ── check sddm user can read video ───────────────────────────
if id sddm >/dev/null 2>&1; then
    if sudo -u sddm test -r "$DEST/Backgrounds/BABU.mp4"; then
        info "sddm user can read the video"
    else
        warn "sddm user cannot read the video — check /usr/share permissions"
    fi
else
    warn "sddm user not found yet; video read access not verified"
fi

# ── SDDM theme configuration ──────────────────────────────────
TIMESTAMP=$(date +%s)
sudo mkdir -p /etc/sddm.conf.d

if sudo test -f "$SDDM_CONF"; then
    BACKUP="${SDDM_CONF}.bak.${TIMESTAMP}"
    sudo cp -a -- "$SDDM_CONF" "$BACKUP"
    info "Backed up $SDDM_CONF → $BACKUP"
    TMPCONF=$(mktemp)
    sudo cat "$SDDM_CONF" > "$TMPCONF"
    awk '
        BEGIN { in_theme=0; theme_seen=0; current_seen=0 }
        /^\[/ {
            if (in_theme && !current_seen) { print "Current=sddm-babu-theme"; current_seen=1 }
            in_theme = ($0 == "[Theme]")
            if (in_theme) theme_seen=1
            print; next
        }
        in_theme && /^[[:space:]]*Current=/ {
            if (!current_seen) { print "Current=sddm-babu-theme"; current_seen=1 }
            next
        }
        { print }
        END {
            if (in_theme && !current_seen) print "Current=sddm-babu-theme"
            if (!theme_seen) { print ""; print "[Theme]"; print "Current=sddm-babu-theme" }
        }
    ' "$TMPCONF" | sudo tee "$SDDM_CONF" >/dev/null
    rm -f "$TMPCONF"
else
    printf '[Theme]\nCurrent=sddm-babu-theme\n' | sudo tee "$SDDM_CONF" >/dev/null
    BACKUP="none"
fi
info "SDDM config updated → $SDDM_CONF"

if sudo test -f "$VIRTUALKBD_CONF"; then
    sudo cp -a -- "$VIRTUALKBD_CONF" "${VIRTUALKBD_CONF}.bak.${TIMESTAMP}"
fi
printf '[General]\nInputMethod=qtvirtualkeyboard\n' | sudo tee "$VIRTUALKBD_CONF" >/dev/null
info "Virtual keyboard config written → $VIRTUALKBD_CONF"

# warn if another conf overrides the theme selection
for dir in /etc/sddm.conf.d /usr/lib/sddm/sddm.conf.d; do
    [[ -d "$dir" ]] || continue
    for f in "$dir"/*.conf; do
        [[ -f "$f" ]] || continue
        while IFS= read -r match; do
            warn "Another config may override theme: $f → $match"
        done < <(grep -nE '^[[:space:]]*Current=' "$f" 2>/dev/null || true)
    done
done

# ── video decoder drop-in: force software decode ─────────────
#
# Qt Multimedia's FFmpeg backend tries VAAPI then Vulkan HW decode on Intel Arc.
# Both produce garbled output (wrong stride). Setting this env var makes Qt skip
# all HW decoders and use pure software (CPU) decode.
# Tested: QT_FFMPEG_DECODING_HW_DEVICE_TYPES=none → log shows "No HW decoder found"
#
if sudo test -f "$VIDEO_CONF"; then
    sudo cp -a -- "$VIDEO_CONF" "${VIDEO_CONF}.bak.${TIMESTAMP}"
    info "Backed up $VIDEO_CONF → ${VIDEO_CONF}.bak.${TIMESTAMP}"
fi
printf '[General]\nGreeterEnvironment=QT_FFMPEG_DECODING_HW_DEVICE_TYPES=none\n' \
    | sudo tee "$VIDEO_CONF" >/dev/null
info "Video decoder config written → $VIDEO_CONF"

# warn if another file already sets GreeterEnvironment
# (/etc/sddm.conf takes priority over .d/ files)
for check_file in "$SDDM_CONF"; do
    [[ -f "$check_file" ]] || continue
    while IFS= read -r match; do
        warn "WARNING: $check_file sets GreeterEnvironment (line $match) — /etc/sddm.conf overrides .d/ files and may override $VIDEO_CONF"
    done < <(grep -n 'GreeterEnvironment' "$check_file" 2>/dev/null || true)
done
for dir in /etc/sddm.conf.d /usr/lib/sddm/sddm.conf.d; do
    [[ -d "$dir" ]] || continue
    for f in "$dir"/*.conf; do
        [[ -f "$f" ]] || continue
        # skip the file we just wrote
        [[ "$f" -ef "$VIDEO_CONF" ]] && continue
        while IFS= read -r match; do
            warn "Another drop-in also sets GreeterEnvironment: $f:$match"
        done < <(grep -n 'GreeterEnvironment' "$f" 2>/dev/null || true)
    done
done

# ── enable SDDM for next boot (no start/restart) ──────────────
if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-enabled sddm.service >/dev/null 2>&1; then
        info "SDDM already enabled — no change to service"
    else
        sudo systemctl disable display-manager.service 2>/dev/null || true
        sudo systemctl enable --force sddm.service
        info "SDDM enabled for next boot (not started)"
    fi
else
    warn "systemctl not found — enable SDDM for next boot manually"
fi

# ── summary ───────────────────────────────────────────────────
hr
info "Installation complete!"
hr
printf '\n'
printf '  Theme        →  %s\n'  "$DEST"
printf '  Video        →  %s  (%s MB, %ds)\n' \
    "$DEST/Backgrounds/BABU.mp4" "$FINAL_SIZE_MB" "$FINAL_DUR_INT"
printf '  SDDM config  →  %s\n'  "$SDDM_CONF"
printf '  Video conf   →  %s\n'  "$VIDEO_CONF"
[[ "${BACKUP:-none}" != "none" ]] && \
    printf '  Config bkup  →  %s\n' "$BACKUP"
printf '\n'
printf '\033[1m  Reboot to see your new login screen.\033[0m\n'
printf '\n'
printf '  Preview without rebooting:\n'
printf '    sddm-greeter-qt6 --test-mode --theme %s/\n' "$DEST"
printf '\n'
printf '  Rollback (theme):\n'
[[ "${BACKUP:-none}" != "none" ]] && \
    printf '    sudo cp %s %s\n' "$BACKUP" "$SDDM_CONF"
printf '  Rollback (video decoder drop-in):\n'
printf '    sudo rm -f %s\n' "$VIDEO_CONF"
printf '\n'
