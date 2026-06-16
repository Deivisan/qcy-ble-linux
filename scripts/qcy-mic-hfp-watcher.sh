#!/usr/bin/env bash
# OBSOLETO por padrão: WirePlumber autoswitch já faz A2DP↔HFP.
# Só habilite com QCY_MIC_WATCHER=1 se autoswitch falhar no seu sistema.
set -euo pipefail

if [[ "${QCY_MIC_WATCHER:-0}" != 1 ]]; then
  printf '[qcy-mic-watcher] desligado (use autoswitch WP). Para forçar: QCY_MIC_WATCHER=1\n'
  exit 0
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mac="${QCY_DEVICE_MAC:-84:AC:60:05:55:2C}"
card="bluez_card.${mac//:/_}"
loopback="bluez_input.${mac}"

log() { printf '[qcy-mic-watcher] %s\n' "$*"; }

bluez_source_index() {
  pactl list sources short 2>/dev/null | awk -v n="$loopback" '$2 == n { print $1; exit }'
}

source_output_uses_qcy() {
  local idx="$1"
  pactl list source-outputs 2>/dev/null | awk -v want="$idx" '
    /^Source Output #/ { block=1; src="" }
    block && /^Source:/ { src=$2; gsub(/[^0-9]/,"",src) }
    block && /^$/ { if (src == want) found=1; block=0 }
    END { exit(found?0:1 }
  '
}

ensure_hfp_if_qcy() {
  local idx profile
  idx="$(bluez_source_index || true)"
  [[ -n "$idx" ]] || return 0
  source_output_uses_qcy "$idx" || return 0
  profile="$(pactl list cards 2>/dev/null | awk -v c="$card" '
    $0 ~ "Name: " c { on=1 }
    on && /Active Profile:/ { sub(/.*Active Profile: /, ""); print; exit }
  ')"
  [[ "${profile:-}" == headset* ]] && return 0
  log "Mic QCY em uso → HFP (era ${profile:-?})"
  "$root/scripts/qcy-hfp-profile.sh" set >/dev/null || true
}

log "Watcher legado ativo (sem restore A2DP — autoswitch cuida do retorno)"

pactl subscribe 2>/dev/null | while read -r line; do
  case "$line" in
    *"Event 'new' on source-output"*) ensure_hfp_if_qcy ;;
  esac
done