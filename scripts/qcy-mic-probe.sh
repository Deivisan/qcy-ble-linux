#!/usr/bin/env bash
# Sonda de microfone do QCY H3S — medicao HONESTA, com voz.
#
# Por que este script existe (25/09/2026):
#   Medir rms de uma gravacao em que NINGUEM FALA prova nada. Foi
#   exatamente o erro que fiz antes: "45% das capturas sao silencio" era
#   so o silencio normal de um quarto vazio. A voz e o sinal.
#
# Como usar:
#   ./scripts/qcy-mic-probe.sh            # 1 sessao, 12s, voz a partir do 3s
#   ./scripts/qcy-mic-probe.sh 3          # 3 sessoes seguidas
#   ./scripts/qcy-mic-probe.sh 3 20       # 3 sessoes de 20s
#
# O QUE FAZER: rode o script e FALE normalmente no microfone do fone
# enquanto ele grava (a partir do 3s). O script so mede — nao troca
# perfil, nao forca nada, nao fica de fundo.
#
# Criterio de veredito (pos-janela de 3s, que e o tempo que o fone leva
# pra ligar o mic e desligar o ANC):
#   rms > 80 e pico > 3000  -> VOZ OK
#   rms 20..80              -> VOZ FRACA (mic ligado mas baixo/ruido)
#   rms < 20                -> MUDO de verdade
set -uo pipefail

card="bluez_card.84_AC_60_05_55_2C"
src="bluez_input.84:AC:60:05:55:2C"
out="${TMPDIR:-/tmp}"
settle=3

log() { printf '\033[1;36m%s\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m%s\033[0m\n' "$*"; }
bad() { printf '\033[1;31m%s\033[0m\n' "$*"; }

profile_now() {
  pactl list cards 2>/dev/null | awk -v c="$card" '
    $0 ~ "Name: " c { on=1 }
    on && /Active Profile:/ { print $3; exit }'
}

run_one() {
  local n=$1 secs=$2 wav="$out/qcy-probe-$n.wav"

  log ""
  log "── sessao $n ─────────────────────────────────────"
  log "perfil antes : $(profile_now)"
  if [[ "$(profile_now)" != headset* ]]; then
    log "abrindo o mic (HFP)…"
    pactl set-card-profile "$card" headset-head-unit 2>/dev/null
  else
    log "ja esta em HFP (reaproveitando sessao — o teste que mais importa)"
  fi

  # deixa o fone ligar o mic e desligar o ANC antes de comecar a medir
  log "FALE a partir de agora (ignoramos os primeiros ${settle}s)"
  sleep "$settle"
  timeout "$secs" pw-record --target "$src" "$wav" 2>/dev/null &
  local rec=$!
  sleep "$secs"
  wait "$rec" 2>/dev/null

  if [[ ! -s "$wav" ]]; then
    bad "sessao $n: NADA capturado (arquivo vazio/inexistente)"
    return 1
  fi

  python3 - "$wav" "$settle" "$n" <<'PY'
import math, struct, sys, wave
path, settle, n = sys.argv[1], int(sys.argv[2]), sys.argv[3]
w = wave.open(path)
frames, rate = w.getnframes(), w.getframerate()
raw = w.readframes(frames)
s = struct.unpack("<%dh" % (len(raw) // 2), raw)
if not s:
    print("sessao %s: capturou 0 samples" % n); sys.exit(1)
body = s[settle * rate:]
if not body:
    print("sessao %s: gravacao curta demais (%d s)" % (n, frames / rate)); sys.exit(1)
rms = math.sqrt(sum(x * x for x in body) / len(body))
peak = max(abs(x) for x in body)
dur = len(body) / rate
print("   duracao pos-janela : %.1f s" % dur)
print("   rms                : %.1f" % rms)
print("   pico               : %d" % peak)
if rms > 80 and peak > 3000:
    print("   \033[1;32mVEREDITO: VOZ OK\033[0m")
elif rms >= 20:
    print("   \033[1;33mVEREDITO: VOZ FRACA\033[0m (mic ligou mas baixo/ruidoso)")
else:
    print("   \033[1;31mVEREDITO: MUDO\033[0m (link existe mas nao entra voz)")
PY
  log "perfil depois : $(profile_now)"
  log "audio em      : $wav"
}

n=${1:-1}
secs=${2:-12}
[[ "$n" =~ ^[0-9]+$ ]] || { bad "uso: $0 [sessoes] [segundos]"; exit 2; }
[[ "$secs" =~ ^[0-9]+$ ]] || secs=12

log "sonda do mic QCY H3S — $n sessao(oes) de ${secs}s"
log "fone: 84:AC:60:05:55:2C | settle=${settle}s | medicao por amplitude com voz"
for i in $(seq 1 "$n"); do run_one "$i" "$secs"; done
log ""
log "fim. mande os numeros (rms/pico) de cada sessao."
