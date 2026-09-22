#!/usr/bin/env bash
# Pausa players (via MPRIS/playerctl) quando o QCY entra em HFP/HSP.
# Motivo: o H3S não faz A2DP+HFP simultâneo; com música tocando, o takeover
# do HFP fica incompleto e o SCO captura zeros (ditado mudo).
# Uso: rode como service user (qcy-pause-on-hfp.service) ou manual.
set -uo pipefail

mac="${QCY_DEVICE_MAC:-84:AC:60:05:55:2C}"
card="bluez_card.${mac//:/_}"

need_pause=0

pactl subscribe 2>/dev/null | while read -r line; do
  case "$line" in
    # Gravação iniciada: pausa ANTES da troca de perfil travar com A2DP aberto
    *"Event 'new' on source-output "*)
      echo "qcy-pause: recording started -> pausing players" | systemd-cat -t qcy-pause -p info
      playerctl -a pause 2>/dev/null || true
      ;;
    *"Event 'change' on card "*)
      profile="$(pactl list cards 2>/dev/null | awk -v c="$card" '
        $0 ~ "Name: " c { on=1 }
        on && /Active Profile:/ { sub(/.*Active Profile: /, ""); print; exit }
      ')"
      if [[ "$profile" == headset* ]]; then
        if [[ "$need_pause" == 0 ]]; then
          need_pause=1
          playerctl -a pause 2>/dev/null || true
        fi
      else
        need_pause=0
      fi
      ;;
  esac
done
