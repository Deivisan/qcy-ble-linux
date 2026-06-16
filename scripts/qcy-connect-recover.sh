#!/usr/bin/env bash
# Recupera conexão Bluetooth do QCY H3S quando pairing/conexão quebra.
# Uso: ./scripts/qcy-connect-recover.sh [--force-repair]
set -euo pipefail

mac="${QCY_DEVICE_MAC:-84:AC:60:05:55:2C}"
force_repair=0

log() { printf '\033[1;36m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m%s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m%s\033[0m\n' "$*"; }
fail() { printf '\033[1;31m%s\033[0m\n' "$*"; }

[[ "${1:-}" == "--force-repair" ]] && force_repair=1

ensure_audio_stack() {
  log "Subindo stack de áudio (PipeWire/WirePlumber)..."
  systemctl --user start pipewire pipewire-pulse wireplumber 2>/dev/null || true
  sleep 2
  if ! systemctl --user is-active --quiet pipewire; then
    fail "PipeWire não subiu. Verifique sessão gráfica/plasma."
    exit 1
  fi
}

bt_power_on() {
  bluetoothctl power on >/dev/null 2>&1 || true
  bluetoothctl pairable on >/dev/null 2>&1 || true
}

try_connect() {
  bluetoothctl connect "$mac" 2>&1
}

is_connected() {
  bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes"
}

repair_pairing() {
  warn "Removendo pairing antigo e refazendo..."
  bluetoothctl disconnect "$mac" >/dev/null 2>&1 || true
  bluetoothctl remove "$mac" >/dev/null 2>&1 || true
  sleep 2
  sudo systemctl restart bluetooth
  sleep 3
  bt_power_on
  bluetoothctl --timeout 20 scan on >/dev/null 2>&1 || true
  sleep 5
  bluetoothctl scan off >/dev/null 2>&1 || true
  bluetoothctl pair "$mac"
  bluetoothctl trust "$mac" >/dev/null 2>&1 || true
}

main() {
  log "Recuperação de conexão QCY H3S ($mac)"

  ensure_audio_stack
  bt_power_on

  if is_connected; then
    ok "Já conectado."
    "$(dirname "$0")/qcy-mic-default.sh" 2>/dev/null || true
    exit 0
  fi

  if [[ "$force_repair" == 1 ]]; then
    repair_pairing
  else
    log "Tentando conectar..."
    if ! try_connect; then
      warn "Conexão falhou; iniciando re-pair automático..."
      repair_pairing
    fi
  fi

  sleep 5
  if try_connect && is_connected; then
    ok "QCY H3S conectado."
    pactl list cards short | grep -i bluez || true
    "$(dirname "$0")/qcy-mic-default.sh" 2>/dev/null || true
    exit 0
  fi

  fail "Não conectou. Confirme que o fone está fora do case e longe do celular."
  fail "Tente: $0 --force-repair"
  exit 1
}

main "$@"