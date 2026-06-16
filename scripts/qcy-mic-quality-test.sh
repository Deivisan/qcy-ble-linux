#!/usr/bin/env bash
# Compara CVSD (8 kHz) vs mSBC (16 kHz) no QCY H3S — fale no fone durante cada gravação.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mac="${QCY_DEVICE_MAC:-84:AC:60:05:55:2C}"
card="bluez_card.${mac//:/_}"
source="bluez_input.${mac}"
wp_conf="${XDG_CONFIG_HOME:-$HOME/.config}/wireplumber/wireplumber.conf.d/51-qcy-h3s-bt.conf"
secs="${QCY_TEST_SECONDS:-5}"

log() { printf '\033[1;36m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m%s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m%s\033[0m\n' "$*"; }
fail() { printf '\033[1;31m%s\033[0m\n' "$*"; }

score_wav() {
  python3 - "$1" <<'PY'
import struct, sys, wave
p = sys.argv[1]
w = wave.open(p, "rb")
rate, ch = w.getframerate(), w.getnchannels()
frames = w.readframes(w.getnframes())
if not frames:
    print(f"rate={rate} ch={ch} absmax=0 rms=0.0 ok=0")
    raise SystemExit(1)
fmt = "<" + "h" * (len(frames) // 2)
s = struct.unpack(fmt, frames)
absmax = max(abs(x) for x in s)
rms = (sum(x * x for x in s) / len(s)) ** 0.5
ok = 1 if absmax >= 500 and rms >= 30 else 0
print(f"rate={rate} ch={ch} absmax={absmax} rms={rms:.1f} ok={ok}")
PY
}

set_msbc_in_conf() {
  local enable="$1"
  local val
  val=$([[ "$enable" == 1 ]] && echo true || echo false)
  if grep -q 'bluez5.enable-msbc' "$wp_conf"; then
    sed -i "s/bluez5.enable-msbc = .*/bluez5.enable-msbc = ${val}/" "$wp_conf"
  else
    sed -i "/monitor.bluez.properties = {/a\\  bluez5.enable-msbc = ${val}" "$wp_conf"
  fi
  cp -f "$wp_conf" "$root/config/wireplumber/51-qcy-h3s-bt.conf"
  systemctl --user restart wireplumber
  sleep 3
}

record_mode() {
  local label="$1"
  local profile="$2"
  local out="/tmp/qcy-mic-${label}.wav"

  pactl set-card-profile "$card" "$profile" 2>/dev/null || {
    fail "Perfil $profile indisponível"
    return 1
  }
  sleep 2
  pactl set-default-source "$source" 2>/dev/null || true
  log ">>> FALE NO FONE agora (${secs}s) — modo ${label}"
  rm -f "$out"
  timeout "$secs" pw-record --target "$source" "$out" >/dev/null 2>&1 || true
  if [[ ! -s "$out" ]]; then
    fail "Sem arquivo WAV em ${label}"
    return 1
  fi
  score_wav "$out"
}

apply_msbc() {
  set_msbc_in_conf 1
  ok "mSBC habilitado em $wp_conf — reinicie OpenWhispr/BrowserOS e teste ditado"
  warn "Se ouvir picote/travamento SCO, rode: $0 --restore-cvsd"
}

restore_cvsd() {
  set_msbc_in_conf 0
  ok "CVSD estável restaurado (msbc=false)"
}

main() {
  case "${1:-}" in
    --apply-msbc) apply_msbc; exit 0 ;;
    --restore-cvsd) restore_cvsd; exit 0 ;;
    -h|--help)
      echo "Uso: $0 | $0 --apply-msbc | $0 --restore-cvsd"
      exit 0
      ;;
  esac

  if ! bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes"; then
    fail "QCY não conectado"
    exit 1
  fi

  log "Teste A/B mic — feche gravações em outros apps"
  backup="$(mktemp)"
  cp "$wp_conf" "$backup"

  log "=== 1/2 CVSD (8 kHz) ==="
  set_msbc_in_conf 0
  cvsd_line="$(record_mode cvsd headset-head-unit)" || cvsd_line="ok=0"

  log "=== 2/2 mSBC (16 kHz) ==="
  set_msbc_in_conf 1
  if pactl list cards 2>/dev/null | grep -q 'codec MSBC'; then
    msbc_line="$(record_mode msbc headset-head-unit)" || msbc_line="ok=0"
  else
    warn "Perfil MSBC não apareceu — fone/dongle pode não negociar wideband"
    msbc_line="ok=0"
  fi

  echo ""
  log "Resultados:"
  echo "  CVSD: $cvsd_line"
  echo "  mSBC: $msbc_line"

  if grep -q 'ok=1' <<<"$msbc_line" && grep -q 'ok=1' <<<"$cvsd_line"; then
    ok "Ambos capturaram áudio — mSBC costuma transcrever melhor (16 kHz)"
    echo "  Para aplicar: $0 --apply-msbc"
  elif grep -q 'ok=1' <<<"$msbc_line"; then
    ok "Só mSBC passou — considere --apply-msbc"
  elif grep -q 'ok=1' <<<"$cvsd_line"; then
    warn "Só CVSD passou — mantenha msbc=false (estável)"
    restore_cvsd
  else
    fail "Nenhum modo captou sinal — fale mais alto ou rode qcy-mic-diagnose.sh --record"
    cp "$backup" "$wp_conf"
    systemctl --user restart wireplumber
    exit 1
  fi

  # volta ao padrão do repo se não pediu apply
  if [[ "$(grep 'bluez5.enable-msbc' "$root/config/wireplumber/51-qcy-h3s-bt.conf" | awk '{print $3}')" == "false" ]]; then
    restore_cvsd
  fi
  rm -f "$backup"
}

main "$@"