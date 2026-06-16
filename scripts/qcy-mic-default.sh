#!/usr/bin/env bash
# Registra o microfone QCY como source padrão (Pulse + PipeWire).
# NÃO altera perfil BT — autoswitch WP troca A2DP↔HFP ao usar o mic.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mac="${QCY_DEVICE_MAC:-84:AC:60:05:55:2C}"
always_hfp="${QCY_MIC_ALWAYS_HFP:-0}"
card="bluez_card.${mac//:/_}"
loopback="bluez_input.${mac}"
analog="alsa_input.pci-0000_0a_00.6.analog-stereo"
state_file="${XDG_STATE_HOME:-$HOME/.local/state}/wireplumber/default-nodes"

analog_wp_id() {
  wpctl status 2>/dev/null \
    | awk '/alsa_input/ && /^[[:space:]]*[0-9]+\./ {
        gsub(/^[[:space:]]*/, ""); split($1,a,"."); print a[1]; exit
      }'
}

log() { printf '\033[1;36m%s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m%s\033[0m\n' "$*"; }

loopback_wp_id() {
  local name="$1"
  wpctl status 2>/dev/null \
    | grep -F "$name" \
    | grep -v monitor \
    | head -1 \
    | sed -E 's/.*[^0-9]([0-9]+)\. .*/\1/'
}

wait_loopback_source() {
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    if pactl list sources short 2>/dev/null | awk '{print $2}' | grep -qx "$loopback"; then
      return 0
    fi

    sleep 2
  done
  return 1
}

persist_wp_default() {
  [[ -f "$state_file" ]] || return 0
  if grep -q '^default\.configured\.audio\.source=' "$state_file"; then
    sed -i "s|^default\\.configured\\.audio\\.source=.*|default.configured.audio.source=${loopback}|" "$state_file"
  fi
}

disable_analog_mic() {
  pactl set-source-mute "$analog" 1 2>/dev/null || true
  pactl set-source-volume "$analog" 0% 2>/dev/null || true
  local id
  id="$(analog_wp_id || true)"
  if [[ -n "$id" ]]; then
    wpctl set-mute "$id" 1 2>/dev/null || true
    wpctl set-volume "$id" 0% 2>/dev/null || true
  fi
}

enable_analog_mic() {
  # Só reativa se explicitamente pedido (placa-mãe fica off por padrão)
  [[ "${QCY_ENABLE_ANALOG_MIC:-0}" == 1 ]] || return 0
  pactl set-source-mute "$analog" 0 2>/dev/null || true
  pactl set-source-volume "$analog" 100% 2>/dev/null || true
  local id
  id="$(analog_wp_id || true)"
  if [[ -n "$id" ]]; then
    wpctl set-mute "$id" 0 2>/dev/null || true
    wpctl set-volume "$id" 1.0 2>/dev/null || true
  fi
}

set_qcy_default() {
  local wp_id pactl_def wp_def

  pactl set-default-source "$loopback" 2>/dev/null || true
  pactl set-source-mute "$loopback" 0 2>/dev/null || true
  pactl set-source-volume "$loopback" 100% 2>/dev/null || true

  wp_id="$(loopback_wp_id "$loopback" || true)"
  if [[ -n "$wp_id" ]]; then
    wpctl set-default "$wp_id" 2>/dev/null || true
  fi
  persist_wp_default

  pactl_def="$(pactl get-default-source 2>/dev/null || true)"
  wp_def="$(wpctl status 2>/dev/null | awk '
    /Default Configured Devices/ { in_settings=1; next }
    in_settings && /Audio\/Source/ {
      line=$0
      sub(/.*Audio\/Source[[:space:]]+/, "", line)
      print line
      exit
    }')"

  if [[ "$pactl_def" == "$loopback" && "$wp_def" == "$loopback" ]]; then
    ok "Mic padrão sincronizado: $loopback (wpctl=$wp_id)"
    return 0
  fi

  warn "Desync detectado: pactl=$pactl_def wpctl=$wp_def (esperado $loopback)"
  return 1
}

disable_analog_mic

if ! bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes"; then
  enable_analog_mic
  exit 0
fi

if [[ "$always_hfp" == 1 ]]; then
  "$root/scripts/qcy-hfp-profile.sh" set >/dev/null || true
  sleep 2
fi

if ! wait_loopback_source; then
  warn "Loopback $loopback ainda não existe (HFP perfil ou wireplumber subindo)"
  exit 1
fi

set_qcy_default