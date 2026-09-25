# Kernel btusb para o dongle UGREEN/Barrot 33fa:0012 (QCY H3S)

**Criado:** 25/09/2026 · **Estado:** ✅ aplicado e validado por transcrição

Este documento substitui `KERNEL-BARROT-PATCH-PLAN.md` (que descrevia um plano
de recompilar o kernel e nunca chegou a ser executado como tal).

---

## TL;DR

```bash
./scripts/apply-btusb-esco-count-fix.sh            # instala o btusb patcheado
./scripts/apply-btusb-esco-count-fix.sh --check    # diagnostica
./scripts/apply-btusb-esco-count-fix.sh --rollback # volta ao btusb stock
```

O que o patch faz: faz o `btusb` contar conexões **eSCO** (`ESCO_LINK`) além de
`SCO_LINK` ao decidir o altsetting USB isocrônico. Sem isso, o HFP moderno
(eSCO) nunca sai do altsetting 0 e o microfone não funciona.

---

## O problema

`drivers/bluetooth/btusb.c`, `btusb_notify()` — código **até hoje no upstream**
(7.2.7 e master):

```c
if (hci_conn_num(hdev, SCO_LINK) != data->sco_num) {
        data->sco_num = hci_conn_num(hdev, SCO_LINK);
        data->air_mode = evt;
        schedule_work(&data->work);
}
```

HFP sempre negocia **eSCO** (link type `eSCO` no `btmon`). O kernel registra
essa conexão como `ESCO_LINK`, **não** como `SCO_LINK`. Logo
`hci_conn_num(hdev, SCO_LINK)` devolve `0`, `sco_num` fica `0`, e
`btusb_work()` cai no ramo `else`:

```c
} else {
        usb_kill_anchored_urbs(&data->isoc_anchor);
        ...
}
```

→ **os URBs isócronos nunca sobem, o USB fica em altsetting 0, e o áudio SCO
chega ao userspace como lixo ou silêncio.** Fingerprint no sistema:
`/sys/bus/usb/devices/1-5:1.1/bAlternateSetting` continua `0` mesmo com HFP
ativo.

## O patch

Uma função de 3 linhas:

```c
static inline unsigned int btusb_sco_conn_count(struct hci_dev *hdev)
{
	return hci_conn_num(hdev, SCO_LINK) + hci_conn_num(hdev, ESCO_LINK);
}
```

e as 4 substituições de `hci_conn_num(hdev, SCO_LINK)` →
`btusb_sco_conn_count(hdev)` (duas em `btusb_send_cmd`/`HCI_SCODATA_PKT`, duas
em `btusb_notify`).

## Como compila (sem DKMS, sem recompilar kernel)

O `linux-zen-headers` do Arch **não traz os `.c` do kernel** (só `Kconfig` em
`drivers/bluetooth/`), então DKMS clássico não funciona. Mas build **externo**
funciona: basta o `btusb.c` + os 4 headers privados do mesmo tag.

Receita mesma do AUR [`btusb-qca-0x3004`](https://aur.archlinux.org/packages/btusb-qca-0x3004):

1. Baixar 5 arquivos da tag exata do kernel:
   ```
   drivers/bluetooth/btusb.c  btintel.h  btbcm.h  btrtl.h  btmtk.h
   https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git/plain/drivers/bluetooth/<arquivo>?id=refs/tags/v7.2.7
   ```
   ⚠️ a tag `v7.2.7` **não existe** em `github.com/torvalds/linux`; use
   `git.kernel.org` (linux-stable). `btmtk.h` **difere** entre v7.2 e v7.2.7 —
   pegar a versão errada dá erro de compilação.
2. `Makefile` de 2 linhas: `obj-m += btusb.o` + `make -C /lib/modules/$(uname -r)/build M=$PWD modules`
3. Instalar em `/lib/modules/$(uname -r)/updates/dkms/btusb.ko` + `depmod -a`
   (o `updates/` tem precedência sobre `kernel/` no `modprobe`).
4. `modprobe -r btusb && modprobe btusb`

Dependências: só `gcc`/`make`/`binutils`/`pahole` — **`bc` não é necessário**
(o `bc` do kconfig não é invocado em build externo). Todos já instalados.

## Verificação (não confie no absmax)

O erro mais caro dessa saga foi confiar em `absmax`/`rms` para declarar
sucesso. **Use transcrição.** O kit de validação:

```bash
# 1. ABRIR stream a partir do estado frio e medir por janela de 1s
/tmp/qcy-coldstart.sh /tmp/cap.wav 20

# 2. Analise objetiva: floor de ruido, gaps internos, clipping
python3 /tmp/qcy-audio-analyze.py /tmp/cap.wav

# 3. Verdade final: transcrever
/tmp/stt-venv/bin/python /tmp/qcy-transcribe.py /tmp/cap.wav
```

Resultados reais (25/09/2026):

| Cenário | corrupted SCO | áudio | transcrição |
|---|---|---|---|
| mSBC (alt 3) | **9 812 em 25s** | silêncio (absmax 22) | `e e e e e e e e` |
| CVSD (alt 1) + P1 | 2–3 em 20–30s | voz | ✅ frase completa |

## mSBC: NÃO LIGAR (definitivo, 25/09/2026)

O mSBC foi implementado no driver e negotiated **perfeitamente no ar**:

```
HCI Event: Synchronous Connect Complete
  Link type: eSCO (0x02)   RX/TX packet length: 60   Air mode: Transparent (0x03)
  -> USB isoc altsetting 3, dlen 72, 3799 pacotes capturados
```

E mesmo assim o áudio é **100% mudo**. Motivo: o endpoint isócrono do Barrot no
`alt 3` entrega quadros de **25 bytes** (`wMaxPacketSize 0x0019`), e um frame
mSBC precisa de **72 bytes**. O `btusb_recv_isoc()` tenta remontar 3 quadros
por frame SCO, mas os quadros não fecham em 25 bytes exatos → dessincroniza →
`validate_sco_handle()` rejeita → `corrupted SCO packet` (~400/s) → mudo.

O `altsetting` máximo do Barrot é o 5, com **49 bytes** — insuficiente para
os 72 do mSBC. **É limite de firmware, não de configuração.**

Armadilha extra: com `bluez5.enable-msbc = true`, o BlueZ escolhe **sozinho** o
perfil `headset-head-unit` (codec MSBC, **prioridade 6**) em vez do
`headset-head-unit-cvsd` (prioridade 5) — e o mic fica mudo sem o usuário pedir
nada. É por isso que `enable-msbc = false` é obrigatório.

## force_scofix: deixar LIGADO

`options btusb force_scofix=1` liga `HCI_QUIRK_FIXUP_BUFFER_SIZE` (o workaround
upstream "Bluetooth: btusb: Workaround for spotty SCO quality"). Efeito
colateral: `hci_read_buffer_size()` passa a usar `sco_mtu=64` em vez dos 255 que
o controlador realmente reporta, o que **bloqueia** o caminho alt-3 do mSBC.

Como mSBC está descartado, o bloqueio é irrelevante e vale manter o filtro de
pacote duplicado. Medido: transporte com 666 pacotes eSCO/s **constantes, sem
lacunas**, nos dois lados do A/B.

## Reinício de módulo: como destravar

Depois de `modprobe -r btusb` / `modprobe btusb`, o transporte SCO pode ficar
**wedged** (stream abre mas sai silêncio). Sintoma: `parecord` retorna
`Stream error: No such entity` e o journal repete
`Failure in Bluetooth audio transport .../sep2/fd0`.

Recuperação, em ordem:

```bash
sudo systemctl restart bluetooth
bluetoothctl disconnect 84:AC:60:05:55:2C && sleep 5
bluetoothctl connect  84:AC:60:05:55:2C
./scripts/qcy-mic-default.sh
```

Se `bluetoothctl connect` devolver `br-connection-page-timeout`, o fone não
está respondendo a paging — usually saiu do alcance, foi para o case ou o
cabo USB está plugado (o cabo **desliga o rádio BT** do H3S).

## Rollback

O `.ko` stock nunca é sobrescrito; o override vive só em `updates/dkms/`.
Para voltar:

```bash
./scripts/apply-btusb-esco-count-fix.sh --rollback
```

## Reboot necessário?

**Não.** O override fica em `/lib/modules/<kern>/updates/dkms/btusb.ko` (disco,
não initramfs) e o `modprobe.d` em `/etc/modprobe.d/`. Ambos persistem e são
aplicados no boot seguinte automaticamente. Confirme com:

```bash
cat /sys/module/btusb/version   # deve_print 0.8-barrot1
```

## Histórico

| Data | Evento |
|---|---|
| 2026-06-14 | DKMS `btusb-barrot` criado no CachyOS (kernel 7.0.11-1-cachyos) com patch de eSCO count + bypass de `validate_sco_handle` |
| 2026-06~09 | troca para Arch + `linux-zen`; DKMS perdido, `btusb` volta ao stock do kernel sem patch |
| 2026-09-25 | recriado como build externo `0.8-barrot1`; validado por transcrição; mSBC descartado com medição |
