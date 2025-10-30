#!/usr/bin/env bash
# =============================================================================
# postinstall2.sh — Kiosk Post-Install (Phase 2)
# Version: 2.2.2025-10-29
# Order of operations (after desktop loads):
#   1) Close Welcome/Tour windows
#   2) Open terminal: tail -f kiosk_postinstall_phase2.log
#   3) Open terminal: top for VMware processes
#   4) Update sudoers NOPASSWD
#   5) Install VMware Workstation Pro (best-effort)
#   6) Extract VM from 7z
#   7) Flatten nested win10/
#   8) Locate .vmx
#   9) Patch .vmx
#  10) Create autostart helper + desktop entries
#  11) Trust desktop entries (gio) in user session
#  12) GNOME lock/idle settings
#  13) Disable Phase 2 service
#  14) Print reboot banner
# =============================================================================
set -Eeuo pipefail

# ---------------------------
# Logging / Tracing
# ---------------------------
LOG=${LOG:-/var/log/kiosk_postinstall_phase2.log}
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1
_ts() { date +"%F %T"; }
log() { printf '[%s] %s\n' "$(_ts)" "$*"; }
hr()  { printf '\n[%s] ============================================================\n' "$(_ts)"; }
PS4='+ $(date "+%F %T") [${BASH_SOURCE##*/}:${LINENO}] '
# Auto-enable DEBUG
#DEBUG=${DEBUG:-1}
DEBUG=${DEBUG:-0}
[[ "$DEBUG" == 1 ]] && set -x || true
trap 'rc=$?; log "[ERROR] rc=$rc at line $LINENO: $BASH_COMMAND"; exit $rc' ERR

hr; log "==== Phase 2 start (v2.2) ===="

# ---------------------------
# Configuration (override via env)
# ---------------------------
SEED_DST=${SEED_DST:-/opt/usb-seed}
USER_NAME=${USER_NAME:-ubuntu}
USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6 || true); : "${USER_HOME:="/home/${USER_NAME}"}"
USER_UID=$(id -u "$USER_NAME")

VM_ROOT=${VM_ROOT:-"${USER_HOME}/vms/win10"}
VMX_PATH_DEFAULT=${VMX_PATH_DEFAULT:-"${VM_ROOT}/win10.vmx"}
SPLIT_DIR=${SPLIT_DIR:-"${SEED_DST}/split"}
VM_ARCHIVE=${VM_ARCHIVE:-"${SPLIT_DIR}/win10.7z"}
VMWARE_BUNDLE_PATH=${VMWARE_BUNDLE_PATH:-"${SEED_DST}/VMware-Workstation-Full-25H2-24995812.x86_64.bundle"}
SEVEN_Z=${SEVEN_Z:-/usr/bin/7z}
VMRUN_BIN=${VMRUN_BIN:-/usr/bin/vmrun}
VMWPRO_BIN=${VMWPRO_BIN:-/usr/bin/vmware}
VMPLAYER_BIN=${VMPLAYER_BIN:-/usr/bin/vmplayer}
SYS_AUTOSTART_DIR=${SYS_AUTOSTART_DIR:-/etc/xdg/autostart}
USR_AUTOSTART_DIR="${USER_HOME}/.config/autostart"
USR_APPS_DIR="${USER_HOME}/.local/share/applications"
USR_DESKTOP_DIR="${USER_HOME}/Desktop"

log "CONFIG: SEED_DST=$SEED_DST"
log "CONFIG: USER_NAME=$USER_NAME, USER_HOME=$USER_HOME (UID=$USER_UID)"
log "CONFIG: VM_ROOT=$VM_ROOT, VMX_PATH_DEFAULT=$VMX_PATH_DEFAULT"
log "CONFIG: SPLIT_DIR=$SPLIT_DIR, VM_ARCHIVE=$VM_ARCHIVE"
log "CONFIG: BUNDLE=$VMWARE_BUNDLE_PATH"

# ---------------------------
# Helpers
# ---------------------------
need() { command -v "$1" >/dev/null 2>&1 || { log "[WARN] Missing $1"; return 1; }; }
mkdirp() { log "mkdir -p $1 (owner ${USER_NAME}:${USER_NAME})"; install -d -o "$USER_NAME" -g "$USER_NAME" -m 0755 "$1"; }
normalize_eol() { sed -i 's/\r$//' "$@" 2>/dev/null || true; }
ensure_kv() {
  local f="$1" k="$2" v="$3"; log "Ensuring VMX key: $k=\"$v\""
  if grep -qE "^[[:space:]]*${k}[[:space:]]*=" "$f"; then
    sed -i -E "s|^[[:space:]]*${k}[[:space:]]*=.*|${k} = \"${v}\"|g" "$f"
  else
    echo "${k} = \"${v}\"" >> "$f"
  fi
}
wait_for_user_session() {
  log "Waiting for user session bus (/run/user/${USER_UID}/bus)…"
  for _ in {1..90}; do
    [[ -S "/run/user/${USER_UID}/bus" ]] && loginctl list-sessions 2>/dev/null | awk -v u="$USER_NAME" '$0~u{f=1} END{exit f?0:1}' && { log "User session detected"; return 0; }
    sleep 2
  done
  log "[WARN] No user session bus detected; continuing best-effort"; return 1
}
as_user() {
  sudo -u "$USER_NAME" \
    XDG_RUNTIME_DIR="/run/user/${USER_UID}" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${USER_UID}/bus" \
    DISPLAY=":0" \
    "$@"
}
set_user_bus_env() {
  export DISPLAY=${DISPLAY:-:0}
  export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-"unix:path=/run/user/${USER_UID}/bus"}
}

# =============================================================================
# 1) Close Welcome/Tour then launch monitoring terminals
# =============================================================================
hr; log "Launching welcome killer and monitoring terminals"
install -d -m 0755 /usr/local/bin

cat > /usr/local/bin/kiosk-close-welcome.sh <<'KILLW'
#!/usr/bin/env bash
set -euo pipefail
MARKER="/run/kiosk_welcome_cleared"
rm -f "$MARKER" 2>/dev/null || true
sleep 2
for i in $(seq 1 20); do
  pkill -f gnome-initial-setup || true
  pkill -f org.gnome.Tour || true
  pkill -f ubuntu-welcome || true
  command -v wmctrl >/dev/null 2>&1 && wmctrl -F -c "Welcome to Ubuntu" 2>/dev/null || true
  sleep 1
done
install -D -m 0644 /dev/null "$MARKER"
exit 0
KILLW
chmod 0755 /usr/local/bin/kiosk-close-welcome.sh

cat > /usr/local/bin/kiosk-wait-welcome.sh <<'WAITW'
#!/usr/bin/env bash
set -euo pipefail
MARKER="/run/kiosk_welcome_cleared"
for i in $(seq 1 90); do
  [ -f "$MARKER" ] && exit 0
  sleep 1
done
exit 0
WAITW
chmod 0755 /usr/local/bin/kiosk-wait-welcome.sh

cat > /usr/local/bin/kiosk-top-vmware.sh <<'TOPSH'
#!/usr/bin/env bash
set -euo pipefail
USER_NAME_PLACEHOLDER="{{USER_NAME}}"
get_pids() { pgrep -d ',' -u "$USER_NAME_PLACEHOLDER" vmware || true; }
pids="$(get_pids)"
if [[ -z "$pids" ]]; then
  echo "[INFO] No VMware PIDs yet; waiting up to 60s…"
  for _ in $(seq 1 60); do sleep 1; pids="$(get_pids)"; [[ -n "$pids" ]] && break; done
fi
if [[ -n "$pids" ]]; then
  echo "[INFO] Attaching top to PIDs: $pids"
  exec top -p "$pids" -c
else
  echo "[WARN] Still no VMware PIDs. Showing full top (press q to quit)."
  exec top -c
fi
TOPSH
sed -i -e "s|{{USER_NAME}}|$USER_NAME|g" /usr/local/bin/kiosk-top-vmware.sh
chmod 0755 /usr/local/bin/kiosk-top-vmware.sh

set_user_bus_env
wait_for_user_session || true
as_user bash -lc 'nohup /usr/local/bin/kiosk-close-welcome.sh >/dev/null 2>&1 & disown || true'
as_user bash -lc 'nohup bash -lc "/usr/local/bin/kiosk-wait-welcome.sh && gnome-terminal -- bash -lc \"tail -n +1 -f /var/log/kiosk_postinstall_phase2.log\"" >/dev/null 2>&1 & disown || true'
as_user bash -lc 'sleep 1; nohup bash -lc "/usr/local/bin/kiosk-wait-welcome.sh && gnome-terminal -- bash -lc \"/usr/local/bin/kiosk-top-vmware.sh\"" >/dev/null 2>&1 & disown || true'
log "[INFO] Requested immediate launch of tail/top (deferred until welcome closes)"

# =============================================================================
# 4) Sudoers NOPASSWD
# =============================================================================
hr; log "Sudoers (NOPASSWD) phase"
SUDO_DROP="/etc/sudoers.d/99-${USER_NAME}-nopasswd"
if [[ ! -f "$SUDO_DROP" ]]; then
  echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" | tee "$SUDO_DROP" >/dev/null
  chmod 440 "$SUDO_DROP"
  if ! visudo -cf "$SUDO_DROP"; then
    log "[WARN] visudo validation failed; removing $SUDO_DROP"
    rm -f "$SUDO_DROP"
  fi
else
  log "NOPASSWD already present"
fi

# =============================================================================
# 5) Install/validate VMware Workstation (best-effort)
# =============================================================================
hr; log "Install/validate VMware phase"
if command -v vmrun >/dev/null 2>&1 && command -v vmplayer >/dev/null 2>&1; then
  log "VMware appears installed (vmrun/vmplayer found)."
else
  if [[ -f "$VMWARE_BUNDLE_PATH" ]]; then
    chmod +x "$VMWARE_BUNDLE_PATH" || true
    log "Executing bundle --eulas-agreed --console --required"
    "$VMWARE_BUNDLE_PATH" --eulas-agreed --console --required || log "[WARN] VMware installer exited non-zero (continuing)"
  else
    log "[WARN] Bundle not found: $VMWARE_BUNDLE_PATH"
  fi
fi

# =============================================================================
# 6) Extract VM from 7z (if archive present)
# =============================================================================
hr; log "Extraction phase"
install -d -m 0755 "$VM_ROOT"; chown -R "$USER_NAME":"$USER_NAME" "$VM_ROOT"
if [[ -f "$VM_ARCHIVE" ]]; then
  log "Extracting: $VM_ARCHIVE → $VM_ROOT"
  sudo -u "$USER_NAME" "$SEVEN_Z" x -aoa -o"$VM_ROOT" "$VM_ARCHIVE"
else
  if [[ -f "${SPLIT_DIR}/win10.7z.001" ]]; then
    log "Extracting split set starting at .001 → $VM_ROOT"
    sudo -u "$USER_NAME" "$SEVEN_Z" x -aoa -o"$VM_ROOT" "${SPLIT_DIR}/win10.7z.001"
  elif [[ -f "${SPLIT_DIR}/win10.7z" ]]; then
    log "Extracting split set single-entry → $VM_ROOT"
    sudo -u "$USER_NAME" "$SEVEN_Z" x -aoa -o"$VM_ROOT" "${SPLIT_DIR}/win10.7z"
  else
    log "[INFO] No VM archive found in $SPLIT_DIR (skipping extraction)"
  fi
fi

# =============================================================================
# 7) Flatten nested win10/ if present
# =============================================================================
hr; log "Flatten check phase"
if [[ -d "${VM_ROOT}/win10" && -f "${VM_ROOT}/win10/win10.vmx" ]]; then
  log "Flattening nested ${VM_ROOT}/win10 → ${VM_ROOT}"
  tmp_move_target="${VM_ROOT}.tmpmove"; install -d -m 0755 "$tmp_move_target"
  mv "${VM_ROOT}/win10/"* "$tmp_move_target"/
  rm -rf "${VM_ROOT}/win10"
  mv "$tmp_move_target"/* "${VM_ROOT}/"
  rmdir "$tmp_move_target" || true
else
  log "No nested win10/ folder requiring flattening"
fi

# =============================================================================
# 8) Locate .vmx
# =============================================================================
hr; log "VMX discovery phase"
VMX_PATH=""
if   [[ -f "${VM_ROOT}/win10.vmx" ]]; then VMX_PATH="${VM_ROOT}/win10.vmx"
elif [[ -f "${VM_ROOT}/win10/win10.vmx" ]]; then VMX_PATH="${VM_ROOT}/win10/win10.vmx"
else VMX_PATH=$(find "$VM_ROOT" -maxdepth 2 -type f -name '*.vmx' | head -n1 || true)
fi
[[ -n "$VMX_PATH" ]] || { log "[ERROR] Could not locate .vmx under $VM_ROOT"; exit 1; }
log "Using VMX: $VMX_PATH"

# =============================================================================
# 9) Clean locks + patch VMX (fullscreen + auto-answer)
# =============================================================================
hr; log "Lock cleanup + VMX patch phase"
find "$(dirname "$VMX_PATH")" -type d -name "*.lck" -exec rm -rf {} + 2>/dev/null || true
ensure_kv "$VMX_PATH" "uuid.action" "keep"
ensure_kv "$VMX_PATH" "msg.autoAnswer" "TRUE"
ensure_kv "$VMX_PATH" "checkpoint.vmState" ""
ensure_kv "$VMX_PATH" "gui.fullscreenAtPowerOn" "TRUE"
ensure_kv "$VMX_PATH" "gui.viewModeAtPowerOn" "fullscreen"
ensure_kv "$VMX_PATH" "pref.vmplayer.fullscreen" "TRUE"
ensure_kv "$VMX_PATH" "pref.autoFitFullScreen" "fitAllDisplays"
ensure_kv "$VMX_PATH" "gui.exitAtPowerOff" "TRUE"
ensure_kv "$VMX_PATH" "isolation.tools.hgfs.disable" "FALSE"

# Warm start/stop (best-effort) just to pre-create runtime files
if command -v vmrun >/dev/null 2>&1; then
  log "Warm start/stop VM (best-effort)"
  vmrun start "$VMX_PATH" nogui || log "[WARN] vmrun start failed (continuing)"
  sleep 5 || true
  vmrun stop "$VMX_PATH" soft || true
else
  log "vmrun not available; skipping warm start"
fi

# =============================================================================
# 10) Autostart helper + Desktop entries
# =============================================================================
hr; log "Autostart + desktop entries phase"
mkdirp "$USR_DESKTOP_DIR"; mkdirp "$USR_APPS_DIR"; mkdirp "$USR_AUTOSTART_DIR"

# Helper launcher script
install -m 0755 -o root -g root /dev/null /usr/local/bin/start-win10-if-not-running.sh
cat > /usr/local/bin/start-win10-if-not-running.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
_ts(){ date +"%F %T"; }; log(){ printf '[%s] %s\n' "$( _ts )" "$*"; }
VMX="{{VMX}}"; VMRUN="{{VMRUN}}"; VMPRO="{{VMPRO}}"; VMPLAYER="{{VMPLAYER}}"
for i in $(seq 1 20); do if lsmod | grep -qE '^(vmmon|vmnet)'; then break; fi; sleep 1; done
find "$(dirname "$VMX")" -type d -name "*.lck" -exec rm -rf {} + 2>/dev/null || true
if command -v "$VMRUN" >/dev/null 2>&1; then
  if "$VMRUN" list 2>/dev/null | grep -Fqx "$VMX"; then log "VM already running"; exit 0; fi
fi
if [ -x "$VMPLAYER" ]; then log "Launching vmplayer -X …"; exec "$VMPLAYER" -X "$VMX"; fi
if [ -x "$VMPRO" ]; then log "Launching vmware -X …";   exec "$VMPRO" -X "$VMX"; fi
if [ -x "$VMRUN" ]; then log "Launching vmrun nogui …";  exec "$VMRUN" -T ws start "$VMX" nogui; fi
log "Fallback: vmware -x …"; exec vmware -x "$VMX"
EOF
sed -i \
  -e "s|{{VMX}}|$VMX_PATH|g" \
  -e "s|{{VMRUN}}|$VMRUN_BIN|g" \
  -e "s|{{VMPRO}}|$VMWPRO_BIN|g" \
  -e "s|{{VMPLAYER}}|$VMPLAYER_BIN|g" \
  /usr/local/bin/start-win10-if-not-running.sh
normalize_eol /usr/local/bin/start-win10-if-not-running.sh

# System-wide autostart (headless safety), but per-user is preferred
install -d -m 0755 "$SYS_AUTOSTART_DIR"
cat > "$SYS_AUTOSTART_DIR/kiosk-start-win10.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=Start Windows 10 VM (Kiosk)
Comment=Starts the Windows 10 VM if not already running
Exec=/usr/local/bin/start-win10-if-not-running.sh
Icon=computer
X-GNOME-Autostart-enabled=true
NoDisplay=true
Terminal=false
DESK
chmod 775 "$SYS_AUTOSTART_DIR/kiosk-start-win10.desktop"
normalize_eol "$SYS_AUTOSTART_DIR/kiosk-start-win10.desktop"

# Per-user autostart (preferred)
cat > "$USR_AUTOSTART_DIR/kiosk-start-win10.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=Start Windows 10 VM (Kiosk)
Comment=Starts the Windows 10 VM if not already running
Exec=/usr/local/bin/start-win10-if-not-running.sh
Icon=computer
X-GNOME-Autostart-enabled=true
NoDisplay=true
Terminal=false
DESK

# Desktop launchers: Start VM, VMware Workstation, VMware Player, View Logs
cat > "$USR_DESKTOP_DIR/Start-Windows-VM.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=Start Windows VM (Kiosk)
Comment=Starts the Windows 10 VM if not already running
Exec=/usr/local/bin/start-win10-if-not-running.sh
Icon=computer
Terminal=false
NoDisplay=false
DESK

cat > "$USR_DESKTOP_DIR/VMware-Workstation.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=VMware Workstation Pro
Exec=${VMWPRO_BIN}
Icon=vmware-workstation
Terminal=false
NoDisplay=false
EOF

cat > "$USR_DESKTOP_DIR/VMware-Player.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=VMware Player
Exec=${VMPLAYER_BIN}
Icon=vmware-player
Terminal=false
NoDisplay=false
EOF

# Log viewer desktop links

cat > "$USR_DESKTOP_DIR/View-Phase-2-Log.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=View Phase 2 Log
Exec=gnome-terminal -- bash -lc 'less -R "/var/log/kiosk_postinstall_phase2.log"'
Icon=text-x-log
Terminal=false
NoDisplay=false
DESK
cat > "$USR_DESKTOP_DIR/View-Phase-1-Log.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=View Phase 1 Log
Exec=gnome-terminal -- bash -lc 'less -R "/var/log/kiosk_postinstall_phase1.log"'
Icon=text-x-log
Terminal=false
NoDisplay=false
DESK

# Ownership, normalize, and permissions for all *.desktop in Desktop
chown "$USER_NAME":"$USER_NAME" "$USR_DESKTOP_DIR"/*.desktop
normalize_eol "$USR_DESKTOP_DIR"/*.desktop
chmod 755 "$USR_DESKTOP_DIR"/*.desktop

# Also place selected app launchers in user applications dir
install -d -m 0755 "$USR_APPS_DIR"
cp -f "$USR_DESKTOP_DIR/Start-Windows-VM.desktop" "$USR_APPS_DIR/start-windows-vm.desktop"
chmod 755 "$USR_APPS_DIR"/*.desktop
chown "$USER_NAME":"$USER_NAME" "$USR_APPS_DIR"/*.desktop

# =============================================================================
# 11) Trust desktop entries via gio in the *user* session
# =============================================================================
hr; log "Trusting desktop entries via gio (user session)"
set_user_bus_env
wait_for_user_session || true
as_user bash -lc '
  set -euo pipefail
  D="$HOME/Desktop"
  mkdir -p "$D"
  for f in "$D"/*.desktop; do
    [ -e "$f" ] || continue
    chmod 755 "$f"
    gio set -t string "$f" metadata::trusted true || true
  done
'

# =============================================================================
# 12) GNOME: Disable lock + idle + hide welcome autostarts
# =============================================================================
hr; log "GNOME settings phase"
set_user_bus_env
wait_for_user_session || true
log "Disable screensaver lock";         as_user gsettings set org.gnome.desktop.screensaver lock-enabled false || true
log "Disable idle timeout (uint32 0)";  as_user gsettings set org.gnome.desktop.session idle-delay 'uint32 0' || true
log "Disable lock on suspend";          as_user gsettings set org.gnome.desktop.screensaver ubuntu-lock-on-suspend false || true
log "Mark initial setup done";          touch /var/lib/gnome-initial-setup-done || true
for f in \
  /etc/xdg/autostart/gnome-initial-setup-first-login.desktop \
  /etc/xdg/autostart/org.gnome.Tour.desktop \
  /etc/xdg/autostart/ubuntu-welcome.desktop; do
  if [[ -f "$f" ]]; then
    sed -i 's/^Hidden=.*/Hidden=true/g' "$f" || true
    grep -q '^Hidden=' "$f" || echo 'Hidden=true' >> "$f"
    sed -i 's/^NoDisplay=.*/NoDisplay=true/g' "$f" || true
    grep -q '^NoDisplay=' "$f" || echo 'NoDisplay=true' >> "$f"
  fi
done

# =============================================================================
# 13) Finish — self-disable service and exit cleanly
# =============================================================================
hr; log "Phase 2 complete — disabling service if present"
if systemctl list-unit-files | grep -q '^kiosk-postinstall2.service'; then
  systemctl disable kiosk-postinstall2.service || true
  systemctl daemon-reload || true
fi

# =============================================================================
# 14) Reboot banner
# =============================================================================
hr
log "Kiosk Phase 2 tasks completed."
log "Please REBOOT this host to finalize the environment."
log "Please REBOOT this host to finalize the environment."
log "Please REBOOT this host to finalize the environment."
hr
exit 0
