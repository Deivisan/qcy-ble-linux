#!/usr/bin/env bash
# Perfil HFP preferido: mSBC (headset-head-unit) com fallback CVSD.
set -euo pipefail

mac="${QCY_DEVICE_MAC:-84:AC:60:05:55:2C}"
card="bluez_card.${mac//:/_}"

hfp_profile_msbc() {
  pactl list cards 2>/dev/null | awk -v c="$card" '
    $0 ~ "Name: " c { on=1 }
    on && /headset-head-unit:/ && /MSBC/ { print "headset-head-unit"; exit }
    on && /headset-head-unit:/ && !/cvsd/ { print "headset-head-unit"; exit }
  '
}

hfp_profile_cvsd() {
  if pactl list cards 2>/dev/null | awk -v c="$card" '
    $0 ~ "Name: " c { on=1 }
    on && /headset-head-unit-cvsd/ { print "yes"; exit }
  ' | grep -q yes; then
    echo "headset-head-unit-cvsd"
  else
    echo "headset-head-unit"
  fi
}

set_hfp_profile() {
  local msbc cvsd
  msbc="$(hfp_profile_msbc || true)"
  cvsd="$(hfp_profile_cvsd)"
  if [[ -n "$msbc" ]] && pactl set-card-profile "$card" "$msbc" 2>/dev/null; then
    echo "$msbc"
    return 0
  fi
  pactl set-card-profile "$card" "$cvsd" 2>/dev/null && echo "$cvsd"
}

case "${1:-}" in
  msbc) hfp_profile_msbc ;;
  cvsd) hfp_profile_cvsd ;;
  set) set_hfp_profile ;;
  *) echo "Uso: $0 {msbc|cvsd|set}" >&2; exit 1 ;;
esac