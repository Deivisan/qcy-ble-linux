#!/usr/bin/env bash
set -euo pipefail

mac="${QCY_DEVICE_MAC:-84:AC:60:05:55:2C}"
card="bluez_card.${mac//:/_}"
source="bluez_input.${mac}"
conf="/etc/wireplumber/wireplumber.conf.d/50-bt-hfp-fix.conf"
user_conf="$HOME/.config/wireplumber/wireplumber.conf.d/50-bluetooth.conf"

log() { printf '\033[1;36m%s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m%s\033[0m\n' "$*"; }
fail() { printf '\033[1;31m%s\033[0m\n' "$*"; }

write_conf() {
  local msbc="$1"
  local label="$2"
  sudo install -d -m 0755 "$(dirname "$conf")"
  sudo tee "$conf" >/dev/null <<EOF
# qcy h3s + ugreen bt6: gerado por scripts/qcy-mic-recover.sh
# modo validado por captura real: ${label}
monitor.bluez.properties = {
  bluez5.enable-msbc = ${msbc}
  bluez5.enable-sbc-xq = true
  bluez5.hfphsp-backend = "native"
  bluez5.hw-offload-sco = false
  bluez5.roles = [ a2dp_sink a2dp_source hsp_hs hfp_hf hfp_ag ]
}

monitor.bluez.rules = [
  {
    matches = [ { device.name = "${card}" } ]
    actions = {
      update-props = {
        bluez5.auto-connect = [ hfp_hf hsp_hs a2dp_sink ]
        device.profile = "headset-head-unit"
        bluez5.hw-volume = [ ]
      }
    }
  }
]

wireplumber.settings = {
  bluetooth.use-persistent-storage = false
  bluetooth.autoswitch-to-headset-profile = true
}
EOF
}

restart_stack() {
  log "🔁 reiniciando stack bluetooth/áudio..."
  bluetoothctl disconnect "$mac" >/dev/null 2>&1 || true
  sleep 1
  systemctl --user restart wireplumber pipewire pipewire-pulse
  sudo systemctl restart bluetooth
  sleep 4
  bluetoothctl connect "$mac" >/dev/null 2>&1 || true
  sleep 6
}

prepare_profile() {
  if ! pactl list short cards | rg -q "${card}"; then
    return 1
  fi
  pactl set-card-profile "$card" headset-head-unit >/dev/null 2>&1 || return 1
  sleep 3
  pactl set-source-mute "$source" 0 >/dev/null 2>&1 || return 1
  pactl set-source-volume "$source" 100% >/dev/null 2>&1 || true
  pactl set-default-source "$source" >/dev/null 2>&1 || true
}

capture_score() {
  local wav="$1"
  rm -f "$wav"
  timeout 7 pw-record --target "$source" "$wav" >/dev/null 2>&1 || true
  python - "$wav" <<'PY'
import json, math, os, struct, sys, wave
p=sys.argv[1]
res={"ok":False,"exists":os.path.exists(p),"size":os.path.getsize(p) if os.path.exists(p) else 0,"rms":0,"absmax":0,"nonzero":0,"samples":0,"rate":0,"channels":0,"sampwidth":0}
try:
    with wave.open(p,'rb') as w:
        data=w.readframes(w.getnframes())
        sw=w.getsampwidth(); ch=w.getnchannels(); rate=w.getframerate()
        if sw == 2:
            vals=struct.unpack('<'+'h'*(len(data)//2), data)
        elif sw == 4:
            vals=struct.unpack('<'+'i'*(len(data)//4), data)
        elif sw == 1:
            vals=tuple(b-128 for b in data)
        else:
            vals=()
        nz=sum(v != 0 for v in vals)
        mx=max((abs(v) for v in vals), default=0)
        rms=math.sqrt(sum(v*v for v in vals)/len(vals)) if vals else 0
        res.update({"rms":round(rms,3),"absmax":mx,"nonzero":nz,"samples":len(vals),"rate":rate,"channels":ch,"sampwidth":sw})
        res["ok"] = bool(len(vals) and nz > 100 and mx > 5 and rms > 0.02)
except Exception as e:
    res["error"] = str(e)
print(json.dumps(res, ensure_ascii=False))
sys.exit(0 if res["ok"] else 1)
PY
}

active_profile() {
  pactl list cards \
    | awk -v card="$card" '
      $0 ~ /^Card #/ { in_card=0 }
      index($0, "Name: " card) { in_card=1 }
      in_card && /Active Profile:/ { sub(/.*Active Profile: /, ""); print; exit }
    '
}

capture_with_retries() {
  local label="$1"
  local wav="/tmp/qcy-${label}.wav"
  local score code profile
  for attempt in 1 2 3 4; do
    log "🎙️ captura ${label}, tentativa ${attempt}/4..."
    pactl set-card-profile "$card" headset-head-unit >/dev/null 2>&1 || true
    sleep 4
    profile="$(active_profile || true)"
    if [[ "$profile" != headset-head-unit* ]]; then
      warn "⚠️ perfil ainda não é hfp (${profile:-nenhum}); rearmando..."
      sleep 3
      continue
    fi
    pactl set-source-mute "$source" 0 >/dev/null 2>&1 || true
    pactl set-source-volume "$source" 100% >/dev/null 2>&1 || true
    pactl set-default-source "$source" >/dev/null 2>&1 || true

    # primeira leitura depois de reconnect pode vir zerada; descarta warmup curto.
    timeout 2 pw-record --target "$source" "/tmp/qcy-${label}-warmup.wav" >/dev/null 2>&1 || true
    sleep 1

    set +e
    score="$(capture_score "$wav")"
    code=$?
    set -e
    echo "$score"
    if [[ "$code" == 0 ]]; then
      ok "✅ ${label} passou; wav: ${wav}"
      return 0
    fi
    warn "⚠️ ${label} ainda sem sinal real nesta tentativa"
  done
  return 1
}

try_mode() {
  local msbc="$1"
  local label="$2"
  log "🧪 testando ${label}..."
  write_conf "$msbc" "$label"
  restart_stack
  if ! prepare_profile; then
    fail "❌ perfil/source hfp não ficou disponível em ${label}"
    return 1
  fi
  if capture_with_retries "$label"; then
    return 0
  fi
  fail "❌ ${label} falhou por sinal real"
  return 1
}

main() {
  log "🔧 recuperação completa do microfone qcy (${mac})"

  if [[ -f "$user_conf" ]]; then
    warn "⚠️ desativando config de usuário conflitante: ${user_conf}"
    mv "$user_conf" "${user_conf}.disabled-by-qcy-recover-$(date +%Y%m%d_%H%M%S)"
  fi

  # primeiro o modo estável para este dongle/kernel: cvsd (msbc=false). se falhar, tenta msbc.
  if try_mode false cvsd; then
    ok "🎙️ microfone restaurado em cvsd estável"
    exit 0
  fi

  if try_mode true msbc; then
    ok "🎙️ microfone restaurado em msbc"
    exit 0
  fi

  fail "🛑 nenhum modo captou sinal real. tente re-pair físico do fone e rode de novo."
  exit 1
}

main "$@"
