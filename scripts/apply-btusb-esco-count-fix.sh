#!/usr/bin/env bash
# Compila e instala btusb 0.8-barrot4 (Barrot legacy SCO) para o dongle
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
marker="HCI_QUIRK_BROKEN_ENHANCED_SETUP_SYNC_CONN"
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

# ---------------------------------------------------------------------------
# P1 — REMOVIDO em 28/09/2026. A premissa era FALSA e o patch era NOCIVO.
#
# include/net/bluetooth/hci_core.h (kernel instalado, 7.2.7-zen1-1):
#     static inline unsigned int hci_conn_num(struct hci_dev *hdev, __u8 type) {
#         switch (type) {
#         case SCO_LINK:
#         case ESCO_LINK:            <-- fallthrough
#             return h->sco_num;     <-- o MESMO contador
#     ...
#
# Entao hci_conn_num(SCO_LINK) == hci_conn_num(ESCO_LINK) SEMPRE. Somar os dois
# devolvia 2*sco_num. E data->sco_num e USADO COMO INDICE DE ARRAY em
# btusb_work():
#     static const int alts[3] = { 2, 4, 5 };
#     sco_idx = min_t(unsigned int, data->sco_num - 1, ARRAY_SIZE(alts) - 1);
#     new_alts = alts[sco_idx];
#
# Com 1 conexao SCO real: correto -> alts[0] = 2 (17 bytes).
# Com P1 (dobrava):               -> alts[1] = 4 (33 bytes)  <-- ERRADO
# Com 2+ conexoes:                -> indice fora de alts[3]   <-- OOB
#
# O endpoint isocronico ficava com wMaxPacketSize errado para o trafego SCO
# (60 bytes por pacote CVSD) -> remontagem quebrada -> link看起来 saudavel
# (HCI sempre_OK, ~600 pkt/s, zero erro de kernel) mas audio SILENCIOSO.
#
# ALTERADO: o que o modulo PATCHEADO entregava era um alt setting que o
# upstream nunca escolhe para 1 conexao, num dongle cujo altsetting correto
# foi validado pelo proprio commit do Barrot (7722d6fb54e4, v6.18+).
# ---------------------------------------------------------------------------
if "btusb_sco_conn_count" in t:
    raise SystemExit("P1 ainda presente na fonte — workdir velho? apague $work")

# ---------------------------------------------------------------------------
# P3 — Barrot 33fa:0010/0012: CVSD precisa de alt >= 2 no endpoint isocronico.
#
# O bug real, medido em 28/09/2026 neste hardware:
#
#   btusb_work(), ramo CVSD:
#       if (hdev->voice_setting & 0x0020) {   // bit 0x0020 = 2EV3
#               static const int alts[3] = { 2, 4, 5 };   // -> alt 2 p/ 1 conexao
#               new_alts = alts[sco_idx];
#       } else {
#               new_alts = data->sco_num;     // -> alt 1 (9 bytes)
#       }
#
# O Barrot NAO anuncia 2EV3 (voice_setting & 0x0020 == 0), entao cai no else e
# fica em alt 1 = wMaxPacketSize 9 bytes. Um pacote SCO CVSD tem 60 bytes
# (8 kHz, 7,5 ms) e precisa ser remontado de ~7 microframes de 9 bytes; a
# remontagem isocronica do btusb nao aguenta esse recorte nesse endpoint ->
# "~400 corrupted SCO packet/s" e audio 100% mudo, com o HCI reportando o
# link como saudavel (Synchronous Connect Complete: Success, ~600 pkt/s).
#
# Correcao: para BTUSB_BARROT usar a MESMA tabela que o upstream usa quando o
# chip suporta 2EV3 (alt 2 = 17 bytes para 1 conexao, 4 e 5 para 2 e 3). Isso
# nao inventa numero nenhum — reaproveita a tabela e o indice validados do
# proprio upstream, com data->sco_num intacto.
# ---------------------------------------------------------------------------
# P3: novo flag de runtime (o padrao do proprio driver, como
# BTUSB_USE_ALT3_FOR_WBS / BTUSB_BROKEN_ISOC). BIT(30) esta livre.
p3flag = "#define BTUSB_BROKEN_SCO_ALT\t\tBIT(30)\n"
flag_anchor = "#define BTUSB_BROKEN_EXT_SCAN\t\tBIT(29)"
if t.count(flag_anchor) != 1:
    raise SystemExit("P3: ancora de defines nao encontrada")
t = t.replace(flag_anchor, flag_anchor + "\n" + p3flag, 1)

p3old = """\t\tif (data->air_mode == HCI_NOTIFY_ENABLE_SCO_CVSD) {
\t\t\tif (hdev->voice_setting & 0x0020) {"""
p3new = """\t\tif (data->air_mode == HCI_NOTIFY_ENABLE_SCO_CVSD) {
\t\t\tif (hdev->voice_setting & 0x0020 ||
\t\t\t    test_bit(BTUSB_BROKEN_SCO_ALT, &data->flags)) {"""
if t.count(p3old) != 1:
    raise SystemExit("P3: ancora do ramo CVSD nao encontrada")
t = t.replace(p3old, p3new, 1)

# liga a flag no probe, junto dos outros flags de quirk
p3probe_old = """\tif (id->driver_info & BTUSB_BROKEN_ISOC)
\t\tdata->isoc = NULL;"""
if t.count(p3probe_old) != 1:
    raise SystemExit("P3: ancora do probe nao encontrada")
t = t.replace(p3probe_old,
    "\t/* Barrot 33fa:0010/0012 nao anuncia 2EV3 (voice_setting 0x0020 = 0), mas\n"
    "\t * precisa de alt >= 2 para o endpoint isocronico remontar os pacotes\n"
    "\t * SCO CVSD de 60 bytes. Sem isso fica em alt 1 (9 bytes) e o audio vira\n"
    "\t * ~400 'corrupted SCO packet'/s com o HCI reportando o link como OK.\n"
    "\t * Reaproveita a tabela e o indice que o upstream usa no caminho 2EV3.\n"
    "\t */\n"
    "\tif (id->driver_info & BTUSB_BARROT)\n"
    "\t\tset_bit(BTUSB_BROKEN_SCO_ALT, &data->flags);\n\n" + p3probe_old, 1)


# ---------------------------------------------------------------------------
# P2 — Barrot 33fa:0010/0012: Enhanced Setup SCO (0x043d) nao funciona ->
# usa o comando classico (0x0028). Mesmo padrao que o upstream aplica em QCA
# e MediaTek. Precedente identico e recente: patch btmtk de mai/2026 para o
# MT6639 descreve EXATAMENTE isto — o firmware anuncia 0x043d, rejeita em
# runtime, o mic fica em silencio, e "the Windows driver works around the
# same firmware bug by issuing the classic Setup Synchronous Connection
# command (0x0428)". Como o mesmo par dongle+fone funciona perfeito no
# Windows, este e o caminho que o proprio Windows usa.
# ---------------------------------------------------------------------------
p2anchor = "\tif (id->driver_info & BTUSB_BCM2045)\n\t\thci_set_quirk(hdev, HCI_QUIRK_BROKEN_STORED_LINK_KEY);"
if t.count(p2anchor) != 1:
    raise SystemExit("P2: ancora BCM2045 nao encontrada")
t = t.replace(p2anchor, p2anchor +
    "\n\n\t/* Barrot 33fa:0010/0012: firmware anuncia Enhanced Setup SCO (0x043d)\n"
    "\t * mas rejeita em runtime -> cai para o comando classico (0x0028), como\n"
    "\t * o driver do Windows. Precedente: btmtk MT6639 (mai/2026).\n"
    "\t */\n"
    "\tif (id->driver_info & BTUSB_BARROT)\n"
    "\t\thci_set_quirk(hdev, HCI_QUIRK_BROKEN_ENHANCED_SETUP_SYNC_CONN);", 1)
if t.count('#define VERSION "0.8"') != 1:
    raise SystemExit("VERSION nao encontrado")
t = t.replace('#define VERSION "0.8"', '#define VERSION "0.8-barrot4"', 1)
open(p, "w").write(t)
print("patches P2 (legacy SCO 0x0028) + P3 (CVSD alt>=2) aplicados -> 0.8-barrot4 | P1 removido")
PY
  grep -q "0.8-barrot4" "$work/btusb.c" || fail "VERSION barrot4 nao aplicada"
  grep -q "btusb_sco_conn_count" "$work/btusb.c" && fail "P1 nao deveria existir"
  grep -q "BTUSB_BROKEN_SCO_ALT" "$work/btusb.c" || fail "P3 nao aplicou"
  ok "btusb.c patcheado (P2 + P3)"
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
  [[ "$(cat /sys/module/btusb/version)" == "0.8-barrot4" ]] || fail "versao em uso != 0.8-barrot4 (rollback manual pode ser necessario)"
  ok "modulo 0.8-barrot4 carregado"
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
