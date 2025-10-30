#!/usr/bin/env bash
# =============================================================================
# kiosk postinstall.sh  — Phase 1 (always executed inside curtin chroot)
#  - Stages offline media to /opt/usb-seed
#  - Installs any .deb payloads (best-effort)
#  - Creates swapfile
#  - Enables GDM autologin + disables lock screen
#  - Registers Phase 2 systemd oneshot
#  - Always exits 0 so Subiquity never fails (reboot handled by user-data)
# =============================================================================
VERSION=1.3.3
BUILD_DATE=2025-10-29

# relaxed error handling inside curtin chroot
set +e +o pipefail
umask 022
set +m
trap - ERR   # disable ERR trap completely

LOG=/var/log/kiosk_postinstall_phase1.log
exec > >(tee -a "$LOG") 2>&1
_ts() { date +"%F %T"; }
msg()  { printf '[%s] %s\n' "$(_ts)" "$*"; }
warn() { printf '[%s] [WARN] %s\n' "$(_ts)" "$*"; }

msg "==== kiosk postinstall.sh start (v${VERSION} ${BUILD_DATE}) ===="

# -----------------------------------------------------------------------------
# basic config
# -----------------------------------------------------------------------------
USB_MEDIA=${USB_MEDIA:-/cdrom/media}
SEED_DST=${SEED_DST:-/opt/usb-seed}
DEB_DIR=${DEB_DIR:-${SEED_DST}/debs}
USER_NAME=${USER_NAME:-ubuntu}
SWAP_GB=${SWAP_GB:-8}

for v in USB_MEDIA SEED_DST DEB_DIR USER_NAME SWAP_GB; do
  eval "msg \"$v=\${$v}\""
done

# -----------------------------------------------------------------------------
# stage offline media
# -----------------------------------------------------------------------------
msg "Staging offline media from $USB_MEDIA → $SEED_DST"
install -d -m 0755 "$SEED_DST"
rsync -avh --delete --info=NAME,STATS "$USB_MEDIA/" "$SEED_DST/" 2>&1
if [[ $? -ne 0 ]]; then
  warn "rsync failed, trying cp -a fallback"
  cp -a "$USB_MEDIA/." "$SEED_DST/" || warn "copy fallback failed"
fi
ls -la "$SEED_DST" || true

# -----------------------------------------------------------------------------
# install offline .debs (best effort)
# -----------------------------------------------------------------------------
if compgen -G "${DEB_DIR}/"'*.deb' >/dev/null 2>&1; then
  msg "Installing .debs from $DEB_DIR"
  apt-get update || warn "apt-get update failed (expected offline)"
  dpkg -i "${DEB_DIR}"/*.deb || warn "dpkg -i non-zero"
  apt-get -f install -y || warn "apt-get -f install non-zero"
else
  msg "No .deb payloads under $DEB_DIR"
fi

# -----------------------------------------------------------------------------
# create swapfile
# -----------------------------------------------------------------------------
msg "Creating ${SWAP_GB} GB swapfile"
SWAPFILE=/swapfile
if ! grep -q 'swapfile' /etc/fstab 2>/dev/null; then
  fallocate -l "${SWAP_GB}G" "$SWAPFILE" 2>/dev/null || \
    dd if=/dev/zero of="$SWAPFILE" bs=1M count=$((SWAP_GB*1024)) status=progress
  chmod 600 "$SWAPFILE"
  mkswap "$SWAPFILE" && swapon "$SWAPFILE"
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
else
  msg "Swapfile already present"
fi
swapon --show || true

# -----------------------------------------------------------------------------
# GDM autologin
# -----------------------------------------------------------------------------
msg "Configuring GDM autologin for ${USER_NAME}"
install -d -m 0755 /etc/gdm3
cat >/etc/gdm3/custom.conf <<EOF
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=${USER_NAME}
EOF

# -----------------------------------------------------------------------------
# disable lock screen / idle
# -----------------------------------------------------------------------------
msg "Writing dconf defaults"
install -d -m 0755 /etc/dconf/db/local.d
cat >/etc/dconf/db/local.d/00-kiosk <<'DCONF'
[org/gnome/desktop/screensaver]
lock-enabled=false
[org/gnome/desktop/session]
idle-delay=uint32 0
[org/gnome/settings-daemon/plugins/power]
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'
power-button-action='nothing'
[org/gnome/desktop/lockdown]
disable-lock-screen=true
DCONF
dconf update || warn "dconf update non-zero"

# -----------------------------------------------------------------------------
# register phase 2 systemd oneshot
# -----------------------------------------------------------------------------
msg "Registering kiosk-postinstall2.service"
UNIT=/etc/systemd/system/kiosk-postinstall2.service
WRAP=/usr/local/sbin/kiosk-phase2.sh
install -d -m0755 /usr/local/sbin /var/lib/kiosk
cat >"$WRAP" <<'WRAP'
#!/usr/bin/env bash
set -e
LOG=/var/log/kiosk_postinstall_phase2.log
exec > >(tee -a "$LOG") 2>&1
echo "$(date +%F\ %T) phase2 start"
[ -f /opt/usb-seed/postinstall2.sh ] && bash /opt/usb-seed/postinstall2.sh
date > /var/lib/kiosk/postinstall2.done
systemctl disable --now kiosk-postinstall2.service || true
echo "$(date +%F\ %T) phase2 done"
WRAP
chmod 0755 "$WRAP"

cat >"$UNIT" <<'UNIT'
[Unit]
Description=Kiosk Phase 2 (VMware + VM extraction + tweaks)
After=graphical.target network-online.target systemd-udev-settle.service
Wants=graphical.target network-online.target
ConditionPathExists=!/var/lib/kiosk/postinstall2.done

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/kiosk-phase2.sh
StandardOutput=journal+console
StandardError=journal+console
TimeoutStartSec=0

[Install]
WantedBy=graphical.target
UNIT

systemctl --no-reload enable kiosk-postinstall2.service || warn "systemctl enable non-zero"

# -----------------------------------------------------------------------------
# completion stamp
# -----------------------------------------------------------------------------
mkdir -p /var/lib/kiosk
date -Iseconds >/var/lib/kiosk/postinstall1.done
msg "Phase 1 complete; reboot will be invoked by user-data."
sync
udevadm settle --timeout=30 || true
msg "==== kiosk postinstall.sh end (exit 0) ===="
exit 0
