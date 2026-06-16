#!/usr/bin/env bash
# Isola userspace vs kernel para o mic HFP do QCY H3S.
# Uso: ./scripts/qcy-hfp-isolation-test.sh
set -euo pipefail

mac="${QCY_DEVICE_MAC:-84:AC:60:05:55:2C}"
card="bluez_card.${mac//:/_}"
loopback_src="bluez_input.${mac}"
real_src="bluez_input.${mac//:/_}.0"
outdir="/tmp/qcy-isolation-$(date +%Y%m%d_%H%M%S)"

log() { printf '\033[1;36m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m%s\033[0m\n' "$*"; }
fail() { printf '\033[1;31m%s\033[0m\n' "$*"; }

score_wav() {
  local wav="$1"
  python3 - "$wav" <<'PY'
import json, math, os, struct, sys, wave
p = sys.argv[1]
res = {"file": p, "ok": False}
if not os.path.exists(p):
    print(json.dumps(res)); sys.exit(1)
with wave.open(p, "rb") as w:
    data = w.readframes(w.getnframes())
    vals = struct.unpack("<" + "h" * (len(data) // 2), data) if data else ()
    nz = sum(v != 0 for v in vals)
    mx = max((abs(v) for v in vals), default=0)
    rms = math.sqrt(sum(v * v for v in vals) / len(vals)) if vals else 0
    res.update({
        "rate": w.getframerate(), "channels": w.getnchannels(),
        "samples": len(vals), "nonzero": nz, "absmax": mx,
        "rms": round(rms, 3),
        "ok": bool(vals and nz > 500 and mx > 200 and rms > 1.0),
    })
print(json.dumps(res, ensure_ascii=False))
sys.exit(0 if res["ok"] else 1)
PY
}

mkdir -p "$outdir"
log "QCY HFP isolation test -> $outdir"

if ! bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes"; then
  fail "QCY não conectado. Ligue o fone (fora do case) e rode: bluetoothctl connect $mac"
  exit 1
fi

log "Etapa A — userspace: HFP fixo"
pactl set-card-profile "$card" headset-head-unit 2>/dev/null || \
  pactl set-card-profile "$card" headset-head-unit-cvsd 2>/dev/null || true
sleep 4

{
  echo "active_profile=$(pactl list cards | awk '/Name: '"$card"'/{f=1} f&&/Active Profile:/{print; exit}')"
  echo "usb_alt=$(cat /sys/bus/usb/devices/1-5:1.1/bAlternateSetting 2>/dev/null || echo unknown)"
  pactl list sources short | grep -i bluez || true
  pw-link -l 2>/dev/null | grep -i bluez || true
} | tee "$outdir/userspace-state.txt"

sudo dmesg -c >/dev/null || true
timeout 6 pw-record --target "$real_src" "$outdir/real-sco.wav" 2>/dev/null || true
timeout 6 pw-record --target "$loopback_src" "$outdir/loopback.wav" 2>/dev/null || true
sudo dmesg | grep -iE 'SCO|corrupt' | tee "$outdir/dmesg-userspace.txt" || true

log "real SCO:"; score_wav "$outdir/real-sco.wav" || true
log "loopback:"; score_wav "$outdir/loopback.wav" || true

log "Etapa B — btmon 10s (fale no fone durante a gravação)"
sudo timeout 10 btmon -i hci0 > "$outdir/btmon.txt" 2>&1 &
btmon_pid=$!
sleep 1
timeout 6 pw-record --target "$real_src" "$outdir/btmon-record.wav" 2>/dev/null || true
wait "$btmon_pid" 2>/dev/null || true

grep -c 'SCO Data' "$outdir/btmon.txt" | tee "$outdir/sco-packet-count.txt"
grep 'SCO Data' "$outdir/btmon.txt" | sed -n 's/.*Handle \([0-9]*\).*/\1/p' | sort | uniq -c | head -10 | tee "$outdir/sco-handles.txt" || true
grep -E 'Sync Conn|Disconnect|AT\+BCS|CIEV' "$outdir/btmon.txt" | head -30 | tee "$outdir/btmon-key-events.txt" || true

log "Etapa C — info módulo btusb"
modinfo btusb | tee "$outdir/btusb-modinfo.txt"
{
  echo "stock=$(md5sum /var/lib/dkms/btusb-barrot/original_module/7.0.11-1-cachyos/x86_64/btusb.ko.zst 2>/dev/null || echo missing)"
  echo "dkms=$(md5sum /lib/modules/$(uname -r)/updates/dkms/btusb.ko.zst 2>/dev/null || echo missing)"
} | tee "$outdir/module-hashes.txt"

ok "Artefatos em $outdir"
log "Mic utilizável = real-sco com absmax > 200 e rms > 1.0"
log "Se loopback falhar mas real-sco passar → problema é PipeWire/UI, não kernel."