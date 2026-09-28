#!/usr/bin/env bash
# Compila e instala btusb 0.8-barrot2 (eSCO-aware SCO count) para o dongle
# UGREEN/Barrot 33fa:0012. Recriado em 25/09/2026 — o DKMS btusb-barrot que o
# projeto usava em 2026-06 se perdeu na troca de distro/kernel (CachyOS -> Arch
# + linux-zen). Ver docs/KERNEL-BTUSB-BARROT.md.
#
# Sem DKMS e sem recompilar o kernel: build externo (receita do AUR
# btusb-qca-0x3004) — baixa so o btusb.c + 4 headers privados da tag exata do
# kernel e compila contra /usr/lib/modules/$(uname -r)/build.
#
# Uso:
#   ./scripts/apply-btusb-esco-count-fix.sh            # instala (padrao)
#   ./scripts/apply-btusb-esco-count-fix.sh --check    # so diagnostica
#   ./scripts/apply-btusb-esco-count-fix.sh --rollback # volta pro btusb stock
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
kern="$(uname -r)"
base_version="${BTUSB_SRC_VERSION:-v7.2.7}"
work="${QCY_BTUSB_WORK:-/tmp/btusb-barrot-7.2.7}"
outdir="/lib/modules/${kern}/updates/dkms"
modprobe_conf="/etc/modprobe.d/btusb-barrot-qcy.conf"
stock="/lib/modules/${kern}/kernel/drivers/bluetooth/btusb.ko.zst"
kbuild="/lib/modules/${kern}/build"
stable="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git/plain/drivers/bluetooth"
marker="btusb_sco_conn_count"
files=(btusb.c btintel.h btbcm.h btrtl.h btmtk.h)

log()  { printf '\033[1;36m%s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m%s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m%s\033[0m\n' "$*"; }
fail() { printf '\033[1;31m%s\033[0m\n' "$*" >&2; exit 1; }

check_only() {
  log "modinfo -n btusb  -> $(modinfo -n btusb)"
  log "versao em uso     -> $(cat /sys/module/btusb/version 2>/dev/null || echo '(modulo nao carregado)')"
  log "force_scofix      -> $(cat /sys/module/btusb/parameters/force_scofix 2>/dev/null || echo '?')"
  log "disable_scofix    -> $(cat /sys/module/btusb/parameters/disable_scofix 2>/dev/null || echo '?')"
  log "modprobe.d        -> $(grep -hE '^options btusb' "$modprobe_conf" 2>/dev/null | tr '\n' ' ' || echo '(ausente)')"
  if [[ -f "$outdir/btusb.ko" ]]; then
    ok "override presente em $outdir/btusb.ko"
  else
    warn "override AUSENTE — rodando o btusb stock do kernel"
  fi
  log "perfis HFP no card:"
  pactl list cards 2>/dev/null | awk -v c="bluez_card.${QCY_DEVICE_MAC:-84:AC:60:05:55:2C}" '
    $0 ~ "Name: " c { on=1 }
    on && /headset-head-unit/ { print "   " $0 }
  ' || true
  log "msbc na config WP -> $(grep -h 'enable-msbc' "${XDG_CONFIG_HOME:-$HOME/.config}/wireplumber/wireplumber.conf.d/51-qcy-h3s-bt.conf" 2>/dev/null || echo '(ausente)')"
}

rollback() {
  warn "removendo override btusb (voltando ao stock do kernel)"
  sudo rm -f "$outdir/btusb.ko"
  sudo depmod -a "$kern"
  sudo modprobe -r btusb 2>/dev/null || true
  sudo modprobe btusb
  sudo systemctl restart bluetooth
  ok "rollback feito. versao em uso: $(cat /sys/module/btusb/version)"
}

fetch() {
  log "baixando drivers/bluetooth de ${base_version} (5 arquivos)"
  mkdir -p "$work"
  for f in "${files[@]}"; do
    curl -fsSL --max-time 60 -o "$work/$f" "$stable/$f?id=refs/tags/${base_version}" \
      || fail "falha ao baixar $f"
  done
  # confere que pegamos mesmo o btusb.c e nao uma pagina de erro do git host
  grep -q "^#define VERSION" "$work/btusb.c" || fail "btusb.c invalido (baixa falhou)"
  grep -q "0x33fa" "$work/btusb.c" || warn "quirk Barrot (0x33fa) ausente neste btusb.c"
  ok "fontes ok ($(wc -l < "$work/btusb.c") linhas em btusb.c)"
}

patch() {
  [[ -f "$work/btusb.c.orig" ]] || cp -a "$work/btusb.c" "$work/btusb.c.orig"
  cp -a "$work/btusb.c.orig" "$work/btusb.c"
  python3 - "$work/btusb.c" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read()
MARK, ESC, CALL = ("hci_conn_num(hdev, SCO_LINK)",
                   "hci_conn_num(hdev, ESCO_LINK)",
                   "btusb_sco_conn_count(hdev)")
n = t.count(MARK)
if n != 4:
    raise SystemExit(f"ancora P1: esperava 4 ocorrencias de SCO_LINK, achei {n} "
                     f"(versao do kernel diferente de {sys.argv[2] if len(sys.argv)>2 else '?'}?)")
t = t.replace(MARK, CALL)          # antes de criar o helper, senao auto-referencia
if t.count(MARK):
    raise SystemExit("P1: sobrou SCO_LINK original")
anchor = "static bool btusb_validate_sco_handle(struct hci_dev *hdev,"
if t.count(anchor) != 1:
    raise SystemExit("P1: ancora validate_sco_handle nao encontrada")
t = t.replace(anchor,
    f"static inline unsigned int btusb_sco_conn_count(struct hci_dev *hdev)\n"
    f"{{\n\treturn {MARK} + {ESC};\n}}\n\n" + anchor, 1)
if t.count(MARK) != 1 or t.count(ESC) != 1 or t.count(CALL) != 4:
    raise SystemExit("P1: helper inconsistente")
# P2: Barrot 33fa:0010/0012 ignora Enhanced Setup SCO sem responder (medido
# 25/09/2026 via btmon: 3 setups emitidos, 1 Synchronous Connect Complete,
# resto sem resposta e sem erro -> mic em silencio). Mesmo padrao que fez o
# upstream marcar QCA e MTK com BROKEN_ENHANCED_SETUP_SYNC_CONN ("doesn't
# seem to work with HSP/HFP"). Volta para legacy Setup SCO (suficiente para
# CVSD 8 kHz; mSBC ja esta desligado e exige eSCO mesmo).
p2anchor = "\tif (id->driver_info & BTUSB_BCM2045)\n\t\thci_set_quirk(hdev, HCI_QUIRK_BROKEN_STORED_LINK_KEY);"
if t.count(p2anchor) != 1:
    raise SystemExit("P2: ancora BCM2045 nao encontrada")
t = t.replace(p2anchor, p2anchor +
    "\n\n\t/* Barrot 33fa:0010/0012: Enhanced Setup SCO sem resposta; HFP via legacy SCO */\n"
    "\tif (id->driver_info & BTUSB_BARROT)\n"
    "\t\thci_set_quirk(hdev, HCI_QUIRK_BROKEN_ENHANCED_SETUP_SYNC_CONN);", 1)
if t.count('#define VERSION "0.8"') != 1:
    raise SystemExit("VERSION nao encontrado")
t = t.replace('#define VERSION "0.8"', '#define VERSION "0.8-barrot2"', 1)
open(p, "w").write(t)
print("patch P1 (eSCO-aware SCO count) + P2 (Barrot legacy SCO) aplicados -> 0.8-barrot2")
PY
  grep -q "$marker" "$work/btusb.c" || fail "patch nao aplicou"
  grep -q "0.8-barrot2" "$work/btusb.c" || fail "VERSION barrot2 nao aplicada"
  ok "btusb.c patcheado"
}

build() {
  cat > "$work/Makefile" <<EOF
obj-m += btusb.o

all:
	make -C $kbuild M=$work modules

clean:
	make -C $kbuild M=$work clean
EOF
  log "compilando modulo externo (sem DKMS, sem fonte completa do kernel)"
  make -C "$work" clean >/dev/null 2>&1 || true
  make -C "$work" 2>&1 | tail -4
  [[ -f "$work/btusb.ko" ]] || fail "build nao gerou btusb.ko"
  ok "gerado $work/btusb.ko ($(stat -c%s "$work/btusb.ko") bytes)"
}

install_mod() {
  log "instalando em $outdir"
  sudo mkdir -p "$outdir"
  sudo cp "$work/btusb.ko" "$outdir/btusb.ko"
  sudo depmod -a "$kern"
  local got; got="$(modinfo -n btusb)"
  [[ "$got" == "$outdir/btusb.ko" ]] || fail "override nao esta em uso (modinfo aponta pra $got) — abortando antes de mexer no modulo carregado"
  ok "gate OK: modinfo aponta pro override"
  sudo modprobe -r btusb 2>/dev/null || fail "nao consegui remover btusb (deve estar em uso) — sem override carregado, estado intacto"
  sudo modprobe btusb
  [[ "$(cat /sys/module/btusb/version)" == "0.8-barrot2" ]] || fail "versao em uso != 0.8-barrot2 (rollback manual pode ser necessario)"
  ok "modulo 0.8-barrot2 carregado"
}

install_conf() {
  if [[ -f "$root/config/kernel/btusb-barrot-qcy.conf" ]]; then
    sudo cp "$root/config/kernel/btusb-barrot-qcy.conf" "$modprobe_conf"
    ok "modprobe.d atualizado a partir do repo"
  else
    warn "$modprobe_conf nao encontrado no repo; mantendo o existente"
  fi
}

case "${1:-}" in
  --check)    check_only ;;
  --rollback) rollback ;;
  "")
    log "kernel: $kern"
    log "tag fonte: $base_version"
    fetch
    patch
    build
    install_mod
    install_conf
    log "reiniciando bluetooth para o fone reconectar"
    sudo systemctl restart bluetooth
    sleep 6
    bluetoothctl connect "${QCY_DEVICE_MAC:-84:AC:60:05:55:2C}" 2>/dev/null | tail -1 || true
    ok "pronto. valide com: ./scripts/qcy-mic-diagnose.sh --record"
    warn "ATENCAO: o transporte SCO pode ficar wedged apos recarregar o modulo."
    warn "Se o mic virar silencio: bluetoothctl disconnect/connect ou restart no bluetooth."
    ;;
  *) fail "opcao desconhecida: $1 (use --check ou --rollback)" ;;
esac
