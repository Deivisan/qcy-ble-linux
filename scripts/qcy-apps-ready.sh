#!/usr/bin/env bash
# Prepara QCY H3S para BrowserOS + OpenWhispr antes de gravar voz.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { printf '\033[1;36m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m%s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m%s\033[0m\n' "$*"; }

log "1/3 — A2DP padrão + mic QCY como default"
QCY_MIC_ALWAYS_HFP=0 "$root/scripts/qcy-mic-default.sh"

log "2/3 — OpenWhispr: desliga 'preferir mic interno'"
"$root/scripts/qcy-openwhispr-mic-fix.sh" || true

log "3/3 — Verificação"
if ! pactl list sources short 2>/dev/null | awk '{print $2}' | grep -qx 'bluez_input.84:AC:60:05:55:2C'; then
  warn "bluez_input ausente — conecte o QCY ou aguarde wireplumber"
  exit 1
fi

ok "Pronto para BrowserOS e OpenWhispr"
echo ""
echo "  • Perfil música: A2DP/AAC (volta sozinho ~12s após parar de gravar)"
echo "  • OpenWhispr → Config → Dictation → 'Preferir microfone interno' = OFF"
echo "  • BrowserOS: feche e abra pelo atalho (wrapper com --ozone-platform=x11)"
echo ""
echo "  Diagnóstico: $root/scripts/qcy-mic-diagnose.sh --record"