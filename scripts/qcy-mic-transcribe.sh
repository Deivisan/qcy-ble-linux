#!/usr/bin/env bash
# VEREDICTO FINAL do mic QCY: transcreve a gravacao.
#
# Por que isso existe: absmax/rms dao falso positivo com frequencia. Runs de
# "PASS" ja foram dados com audio que era ruido de pacote corrompido. A unica
# prova de que o microfone funciona e o texto sair certo.
#
# Uso:
#   ./scripts/qcy-mic-transcribe.sh                 # grava 15s e transcreve
#   ./scripts/qcy-mic-transcribe.sh /tmp/cap.wav    # transcreve arquivo existente
#
# Requer o venv de STT (instala sozinho se faltar):
#   uv venv /tmp/stt-venv && uv pip install --python /tmp/stt-venv/bin/python faster-whisper
set -euo pipefail

VENV="${QCY_STT_VENV:-/tmp/stt-venv}"
MODEL="${QCY_STT_MODEL:-small}"
sec="${QCY_STT_SECONDS:-15}"
mac="${QCY_DEVICE_MAC:-84:AC:60:05:55:2C}"
src="bluez_input.${mac}"
card="bluez_card.${mac//:/_}"

log()  { printf '\033[1;36m%s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m%s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m%s\033[0m\n' "$*"; }
fail() { printf '\033[1;31m%s\033[0m\n' "$*" >&2; exit 1; }

ensure_stt() {
  [[ -x "$VENV/bin/python" ]] && return 0
  log "instalando faster-whisper em $VENV (1x)"
  command -v uv >/dev/null || fail "uv nao encontrado (instale uv ou use o venv manualmente)"
  uv venv "$VENV" >/dev/null
  uv pip install --python "$VENV/bin/python" faster-whisper >/dev/null
  ok "STT pronto"
}

capture() {
  local wav="$1"
  # estado frio: A2DP, sem stream aberto
  pactl set-card-profile "$card" a2dp-sink 2>/dev/null || true
  sleep 2
  log "FALE NO FONE a partir de AGORA por ${sec}s"
  sleep 3
  timeout "$sec" parecord -d "$src" "$wav" 2>/dev/null || true
  [[ -s "$wav" ]] || fail "gravacao vazia — o stream nao abriu (rode scripts/qcy-mic-diagnose.sh --record)"
}

wav="${1:-}"
if [[ -z "$wav" ]]; then
  wav="/tmp/qcy-stt-$(date +%Y%m%d-%H%M%S).wav"
  capture "$wav"
fi

ensure_stt

log "analisando..."
python3 "$(dirname "${BASH_SOURCE[0]}")/qcy-audio-analyze.py" "$wav" || true

log "transcrevendo (modelo=$MODEL) — isto e o veredito real..."
"$VENV/bin/python" "$(dirname "${BASH_SOURCE[0]}")/qcy-transcribe.py" "$wav" "--model=$MODEL"

echo
warn "Interprete: se a transcricao sair com a frase que voce falou = mic OK."
warn "Se sair vazia, 'e e e e' ou ruido: o transporte SCO esta quebrado."
warn "Ver docs/KERNEL-BTUSB-BARROT.md"
