#!/usr/bin/env bash
# Diagnóstico completo do mic QCY H3S — UMA execução, UM veredito.
# Não corrige nada. Só mede cada camada e diz onde quebra.
#
# Uso:
#   ./scripts/qcy-mic-diagnose.sh              # diagnóstico rápido
#   ./scripts/qcy-mic-diagnose.sh --record     # inclui gravação 4s (fale no fone)
#   ./scripts/qcy-mic-diagnose.sh --record --save ~/qcy-debug.txt
#
# Envie o arquivo gerado para o agente. Não precisa explicar nada além disso.
set -euo pipefail

mac="${QCY_DEVICE_MAC:-84:AC:60:05:55:2C}"
card="bluez_card.${mac//:/_}"
loopback="bluez_input.${mac}"
analog="alsa_input.pci-0000_0a_00.6.analog-stereo"
usb_isoc="/sys/bus/usb/devices/1-5:1.1/bAlternateSetting"
ts="$(date +%Y%m%d_%H%M%S)"
out="/tmp/qcy-mic-diagnose-${ts}.txt"
do_record=0
save_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --record) do_record=1; shift ;;
    --save) save_path="${2:?--save precisa de caminho}"; shift 2 ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Opção desconhecida: $1" >&2; exit 2 ;;
  esac
done

RED='\033[1;31m'; GRN='\033[1;32m'; YLW='\033[1;33m'; CYN='\033[1;36m'; RST='\033[0m'
pass() { printf '%b[PASS]%b %s\n' "$GRN" "$RST" "$*"; }
fail() { printf '%b[FAIL]%b %s\n' "$RED" "$RST" "$*"; }
warn() { printf '%b[WARN]%b %s\n' "$YLW" "$RST" "$*"; }
info() { printf '%b[INFO]%b %s\n' "$CYN" "$RST" "$*"; }
section() { printf '\n━━━ %s ━━━\n' "$*"; }

exec > >(tee "$out") 2>&1

section "QCY MIC DIAGNOSE — $ts"
info "MAC=$mac | Saída: $out"

# ── L1: Hardware / conexão ──────────────────────────────────────────
section "L1 — Bluetooth conectado?"
if bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes"; then
  pass "QCY conectado"
else
  fail "QCY NÃO conectado — coloque o fone fora do case e: bluetoothctl connect $mac"
fi

# ── L2: Perfil e HFP disponível ─────────────────────────────────────
section "L2 — Perfil ativo e HFP disponível?"
profile="$(pactl list cards 2>/dev/null | awk -v c="$card" '
  $0 ~ "Name: " c { on=1 }
  on && /Active Profile:/ { sub(/.*Active Profile: /, ""); print; exit }
')"
hfp_avail="$(pactl list cards 2>/dev/null | awk -v c="$card" '
  $0 ~ "Name: " c { on=1 }
  on && /headset-head-unit/ { print "yes"; exit }
')"
info "Perfil ativo: ${profile:-desconhecido}"
if [[ -n "$hfp_avail" ]]; then
  pass "Perfil headset-head-unit disponível no card"
else
  fail "Perfil HFP ausente no card — mic impossível até wireplumber/bluetoothd expor HFP"
fi
if [[ "${profile:-}" == a2dp* ]]; then
  info "Em A2DP (normal para música). Mic precisa de autoswitch ao gravar."
elif [[ "${profile:-}" == headset* ]]; then
  pass "Em HFP — caminho SCO deve estar ativo"
fi

# ── L3: Loopback existe (mic visível no PipeWire) ───────────────────
section "L3 — Loopback bluez_input existe?"
if pactl list sources short 2>/dev/null | awk '{print $2}' | grep -qx "$loopback"; then
  pass "Source Pulse existe: $loopback"
else
  fail "Source $loopback NÃO existe — apps não têm o que selecionar"
  info "Causa comum: wireplumber reiniciou e loopback ainda não criou (espere 10s e rode de novo)"
fi

wp_loopback="$(wpctl status 2>/dev/null | grep -F "$loopback" | grep -v monitor | head -1 || true)"
if [[ -n "$wp_loopback" ]]; then
  pass "Filtro PipeWire existe: $wp_loopback"
else
  fail "Filtro wpctl para $loopback NÃO encontrado"
fi

wp_sources_qcy="$(wpctl status 2>/dev/null | sed -n '/Sources:/,/Filters:/p' | grep -i 'QCY H3S' || true)"
if [[ -n "$wp_sources_qcy" ]]; then
  pass "QCY H3S em wpctl Sources (visível em algumas UIs)"
else
  warn "QCY H3S NÃO em wpctl Sources (só em Filters) — KDE pode esconder sem 'Mostrar dispositivos virtuais'"
fi

# ── L4: Defaults sincronizados (causa #1 de apps não verem mic) ─────
section "L4 — Defaults pactl vs wpctl sincronizados?"
pactl_def="$(pactl get-default-source 2>/dev/null || echo none)"
wp_def="$(wpctl status 2>/dev/null | awk '
  /Default Configured Devices/ { s=1; next }
  s && /Audio\/Source/ { sub(/.*Audio\/Source[[:space:]]+/, ""); print; exit }
')"
state_def="$(grep '^default\.configured\.audio\.source=' \
  "${XDG_STATE_HOME:-$HOME/.local/state}/wireplumber/default-nodes" 2>/dev/null \
  | cut -d= -f2 || echo none)"

info "pactl default  = $pactl_def"
info "wpctl default  = $wp_def"
info "state persist  = $state_def"

if [[ "$pactl_def" == "$loopback" && "$wp_def" == "$loopback" ]]; then
  pass "pactl e wpctl apontam para $loopback"
elif [[ "$pactl_def" == "$loopback" && "$wp_def" == "$analog" ]]; then
  fail "DESSYNC: pactl=BT mas wpctl=placa-mãe — KDE/BrowserOS/OpenWhisper usam wpctl"
  info "Fix conhecido: ./scripts/qcy-mic-default.sh"
elif [[ "$pactl_def" == "$analog" ]]; then
  fail "pactl default é placa-mãe — apps Pulse também não pegam BT"
else
  warn "Defaults inesperados — verifique manualmente"
fi

# ── L5: SCO / USB kernel ────────────────────────────────────────────
section "L5 — Kernel SCO / USB isoc"
usb_alt="$(cat "$usb_isoc" 2>/dev/null | tr -d ' ' || echo na)"
info "USB isoc alt = $usb_alt (0=A2DP normal, 1-6=SCO ativo)"
if [[ "${profile:-}" == headset* && "$usb_alt" != "0" && "$usb_alt" != "na" ]]; then
  pass "USB alt=$usb_alt com HFP — driver eSCO OK"
elif [[ "${profile:-}" == a2dp* ]]; then
  info "USB alt=0 em A2DP é esperado"
else
  warn "HFP ativo mas USB alt=$usb_alt — possível problema no DKMS btusb"
fi

sco_errs="$(dmesg 2>/dev/null | grep -ciE 'SCO packet for unknown|corrupted SCO' || true)"
sco_errs="${sco_errs//$'\n'/}"
sco_errs="${sco_errs:-0}"
info "Erros SCO no dmesg (total sessão): $sco_errs"
if [[ "$sco_errs" -gt 50 ]]; then
  warn "Muitos erros SCO no kernel — áudio pode picotar ou ficar mudo"
fi

if lsmod | grep -q '^btusb'; then
  if modinfo btusb 2>/dev/null | grep -q 'updates/dkms'; then
    pass "btusb DKMS carregado"
  else
    warn "btusb stock (sem DKMS Barrot)"
  fi
fi

# ── L6: Gravação real (opcional) ────────────────────────────────────
section "L6 — Gravação de áudio"
if [[ "$do_record" != 1 ]]; then
  info "Pulado (use --record e FALE NO FONE durante os 4s)"
else
  wav="/tmp/qcy-diagnose-${ts}.wav"
  info "Gravando 4s de $loopback — FALE NO FONE AGORA..."
  timeout 4 parecord -d "$loopback" "$wav" 2>/dev/null || true
  if [[ -f "$wav" ]]; then
    python3 - "$wav" <<'PY'
import math, struct, sys, wave
p = sys.argv[1]
with wave.open(p, "rb") as w:
    d = w.readframes(w.getnframes())
    v = struct.unpack("<" + "h" * (len(d) // 2), d) if d else ()
    mx = max((abs(x) for x in v), default=0)
    rms = math.sqrt(sum(x * x for x in v) / len(v)) if v else 0
    nz = sum(x != 0 for x in v)
print(f"  samples={len(v)} nonzero={nz} absmax={mx} rms={rms:.3f}")
if mx > 200 and rms > 1.0:
    print("  VEREDICTO_GRAVACAO=PASS")
elif mx > 0:
    print("  VEREDICTO_GRAVACAO=WEAK")
else:
    print("  VEREDICTO_GRAVACAO=FAIL_SILENCE")
PY
    profile_after="$(pactl list cards 2>/dev/null | awk -v c="$card" '
      $0 ~ "Name: " c { on=1 }
      on && /Active Profile:/ { sub(/.*Active Profile: /, ""); print; exit }
    ')"
    info "Perfil após gravar: ${profile_after:-?}"
    pwlink="$(pw-link -l 2>/dev/null | grep -i bluez || echo '(sem links)')"
    info "pw-link após gravar:"
    echo "$pwlink" | sed 's/^/  /'
  else
    fail "parecord não gerou arquivo — stream não abriu"
  fi
fi

# ── L7: Config ativa ────────────────────────────────────────────────
section "L7 — Config e serviços"
info "WirePlumber: $(wireplumber --version 2>/dev/null | head -1 || echo ?)"
info "PipeWire: $(pipewire --version 2>/dev/null | head -1 || echo ?)"
info "Configs WP ativas:"
ls -1 "${HOME}/.config/wireplumber/wireplumber.conf.d/"*.conf 2>/dev/null | sed 's/^/  /' || echo "  (nenhuma)"
info "Timer mic-default: $(systemctl --user is-active qcy-mic-default.timer 2>/dev/null || echo inactive)"
info "Autoswitch WP: $(wpctl settings 2>/dev/null | awk '/autoswitch/{getline; print $2; exit}' || echo ?)"

# ── VEREDICTO ───────────────────────────────────────────────────────
section "VEREDICTO — onde está o problema?"
issues=0

bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes" || { fail "→ L1: conectar fone"; ((issues++)) || true; }
[[ -n "$hfp_avail" ]] || { fail "→ L2: perfil HFP ausente — restart wireplumber+bluetooth"; ((issues++)) || true; }
pactl list sources short 2>/dev/null | awk '{print $2}' | grep -qx "$loopback" || { fail "→ L3: loopback não existe"; ((issues++)) || true; }
[[ "$pactl_def" == "$loopback" && "$wp_def" == "$loopback" ]] || {
  fail "→ L4: defaults dessincronizados — rode: ./scripts/qcy-mic-default.sh"
  ((issues++)) || true
}

if [[ "$do_record" == 1 && -f "/tmp/qcy-diagnose-${ts}.wav" ]]; then
  grep -q 'VEREDICTO_GRAVACAO=PASS' "$out" 2>/dev/null && pass "→ L6: áudio real capturado" || {
    fail "→ L6: gravação muda/fraca — problema kernel SCO ou HFP não ativou"
    ((issues++)) || true
  }
fi

echo ""
if [[ "$issues" -eq 0 ]]; then
  pass "Todas as camadas OK no diagnóstico estático."
  if [[ "$do_record" != 1 ]]; then
    warn "Rode com --record (falando no fone) para confirmar áudio real."
  else
    info "Se apps AINDA não veem o mic com tudo PASS:"
    info "  1. KDE → volume → Mais ações → 'Mostrar dispositivos virtuais'"
    info "  2. Selecione 'QCY H3S' em Entrada de áudio"
    info "  3. Se app usa lista própria, reinicie o app APÓS o diagnose PASS"
  fi
else
  fail "$issues camada(s) com problema — corrija na ordem L1→L6 antes de mexer em mais config"
fi

info "Arquivo completo: $out"
if [[ -n "$save_path" ]]; then
  cp "$out" "$save_path"
  info "Cópia salva: $save_path"
fi