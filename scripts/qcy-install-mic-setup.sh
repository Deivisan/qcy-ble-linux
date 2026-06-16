#!/usr/bin/env bash
# Instala/reaplica a configuração de microfone QCY H3S que funciona (Jun/2026).
# Idempotente — pode rodar após clone, reboot ou quando mic "sumir" de novo.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wp_d="${XDG_CONFIG_HOME:-$HOME/.config}/wireplumber/wireplumber.conf.d"
sys_d="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
browseros_d="${HOME}/.local/share/browseros"
desktop_d="${HOME}/.local/share/applications"

log() { printf '\033[1;36m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m%s\033[0m\n' "$*"; }

install_wp() {
  mkdir -p "$wp_d"
  for f in 51-qcy-h3s-bt.conf 52-qcy-disable-analog-mic.conf; do
    cp -f "$root/config/wireplumber/$f" "$wp_d/$f"
    ok "wireplumber: $wp_d/$f"
  done
  # loopback extra quebrou autoswitch — nunca reativar
  if [[ -f "$wp_d/53-qcy-bt-mic-visible.conf" ]]; then
    mv -f "$wp_d/53-qcy-bt-mic-visible.conf" \
      "$wp_d/53-qcy-bt-mic-visible.conf.disabled-breaks-autoswitch"
    log "Desativou 53-qcy-bt-mic-visible.conf (quebra autoswitch)"
  fi
}

install_systemd() {
  mkdir -p "$sys_d"
  for unit in qcy-mic-default.service qcy-mic-hfp-watcher.service qcy-mic-default.timer; do
    sed "s|@REPO_ROOT@|$root|g" "$root/config/systemd-user/$unit" > "$sys_d/$unit"
    ok "systemd: $sys_d/$unit"
  done
  systemctl --user daemon-reload
  systemctl --user enable --now qcy-mic-default.timer
  systemctl --user disable --now qcy-mic-hfp-watcher.service 2>/dev/null || true
  systemctl --user start qcy-mic-default.service || true
}

install_browseros_wrapper() {
  mkdir -p "$browseros_d"
  cp -f "$root/config/browseros/browseros-wrapper.sh" "$browseros_d/browseros-wrapper.sh"
  chmod +x "$browseros_d/browseros-wrapper.sh"
  ok "browseros wrapper: $browseros_d/browseros-wrapper.sh"
  if [[ -f "$desktop_d/browseros.desktop" ]]; then
    if ! grep -q 'browseros-wrapper.sh' "$desktop_d/browseros.desktop"; then
      sed -i 's|Exec=.*|Exec='"$browseros_d/browseros-wrapper.sh"' %U|' "$desktop_d/browseros.desktop"
      ok "browseros.desktop → wrapper"
    fi
  fi
}

apply_openwhispr() {
  if [[ -x "$root/scripts/qcy-openwhispr-mic-fix.sh" ]]; then
    "$root/scripts/qcy-openwhispr-mic-fix.sh" || true
  fi
}

restart_audio() {
  log "Reiniciando wireplumber..."
  systemctl --user restart wireplumber 2>/dev/null || true
  sleep 2
}

log "=== QCY H3S — instalação config de microfone ==="
install_wp
install_systemd
install_browseros_wrapper
restart_audio
apply_openwhispr
QCY_MIC_ALWAYS_HFP=0 "$root/scripts/qcy-mic-default.sh" || true
ok "Instalação concluída. Rode: $root/scripts/qcy-apps-ready.sh antes de gravar voz."