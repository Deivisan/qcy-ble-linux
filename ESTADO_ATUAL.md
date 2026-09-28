# Estado Atual — QCY H3S no Linux

**Atualizado:** 28/09/2026 · **Status:** ✅ Controle SPP/RFCOMM · ✅ Música A2DP/AAC · ✅ **Mic corrigido na raiz e validado** · ✅ Protocolo documentado (72 Cmd IDs)

> ⚠️ Este arquivo mentia sobre o ambiente. Correções de 25/09/2026:
> o sistema é **Arch Linux + COSMIC** com `linux-zen 7.2.7-zen1-1` — não é
> CachyOS/KDE. E o mic **depende de um `btusb` patcheado** que estava
> perdido. Ver `docs/KERNEL-BTUSB-BARROT.md` e `TENTATIVAS-SEM-SUCESSO.md` 17-19.

## O que está funcionando hoje

| Camada | O quê |
|--------|--------|
| Controle fone | `bin/qcy-ctl` via SPP/RFCOMM (ANC, volume, música, game, LDAC) |
| Perfil música | `a2dp-sink` (AAC) |
| Perfil mic | `headset-head-unit` **CVSD 8 kHz** (mSBC inatingível neste dongle) |
| **Kernel** | **`btusb 0.8-barrot4`** em `updates/dkms/` (P2 SCO clássico + P3 altsetting) |
| WirePlumber | `51-qcy-h3s-bt.conf` com `enable-msbc = false` |
| Autoswitch | `bluetooth.autoswitch-to-headset-profile = true` — **nativo, sem daemon** |
| COSMIC | default source estável em `bluez_input`; sem erro de áudio no journal |
| Transcrição | `scripts/qcy-mic-transcribe.sh` (faster-whisper) — veredito real |
| Sonda de mic | `scripts/qcy-mic-probe.sh` — mede amplitude depois da janela de 3 s |

## Correção do microfone (28/09/2026) — a que resolveu

**Causa raiz:** `drivers/bluetooth/btusb.c`, `btusb_work()`. O Barrot
`33fa:0012` **não anuncia 2EV3** (`hdev->voice_setting & 0x0020 == 0`), então o
kernel escolhia **altsetting USB 1 (9 bytes)** para pacotes SCO CVSD de
**60 bytes**. A remontagem isócrona não fecha nesse endpoint.

**Fingerprint (o que faz parecer "saudável"):** `Synchronous Connect Complete:
Status: Success`, ~600 pacotes SCO/s no ar e **zero mensagens de erro no
kernel** — com o áudio chegando mudo ou como zumbido de ~100 Hz.

**Correção:** o patch `btusb 0.8-barrot4` força o Barrot a usar a **mesma tabela
de altsettings e o mesmo índice que o upstream usa no caminho 2EV3**
(`alts[3] = {2,4,5}`) → **altsetting 2 (17 bytes)**. Mais `P2`, que faz o
Barrot usar o comando SCO clássico `0x0028` em vez de `0x043d` — **é o que o
driver do Windows faz**, com precedente upstream idêntico (`btmtk` MT6639,
maio/2026).

**Verificação, não confie só em eu dizer:**

```bash
cat /sys/module/btusb/version                              # 0.8-barrot4
timeout 10 pw-record --target bluez_input.84_AC_60_05_55:2C /tmp/t.wav &
sleep 3; cat /sys/bus/usb/devices/1-5:1.1/bAlternateSetting   # tem que ser 2
dmesg | grep -c "corrupted SCO"                            # tem que ser 0
```

| Cenário (28/09/2026) | altsetting | corrupted SCO | Áudio |
|----------------------|-----------|---------------|-------|
| Antes do patch | 1 | centenas/s | mudo |
| Depois (3 ciclos A2DP↔HFP) | **2** | **0** | **capturado 3/3** |

Validação por **teste acústico diferencial** (tom de 1500 Hz no alto-falante do
notebook, medido no mic do fone): energia na banda do tom subiu **×33.8** em
relação ao silêncio, e os 3 ciclos seguidos deram ×17.9, ×16.2, ×5.6. Detalhes,
teste e receita para outras máquinas em **`docs/KERNEL-BTUSB-BARROT.md`**.

## Ambiente real (verificado, não presumido)

- SO: **Arch Linux** · DE: **COSMIC** (`XDG_CURRENT_DESKTOP=COSMIC`)
- Kernel: `linux-zen 7.2.7-zen1-1` · PipeWire 1.6.9 · WirePlumber 0.5.17 · BlueZ 5.87
- Dongle: UGREEN Barrot `33fa:0012` (`hci0`), quirk `BTUSB_BARROT` upstream
- Wi-Fi em 5 GHz (`wlp7s0`) — sem interferência 2.4 GHz


## Protocolo — engenharia reversa completa (16/08/2026)


**Documento principal:** [`analysis/QCY-H3S-PROTOCOL-COMPLETO.md`](./analysis/QCY-H3S-PROTOCOL-COMPLETO.md)

Análise feita sobre **3 builds do APK oficial** (682, 689, 715):

- **72 Cmd IDs** mapeados (cmd 0x01..0x48 + 0xFE)
- **25 UUIDs GATT** capturados (Service `0000A001`, Char `0000ae00` principal)
- **2 rotas de transporte**: SPP/RFCOMM (funcionando) + GATT Write (identificado, pendente validação)
- **Modos ANC**: básico via SPP `0x0C` (funcionando) + avançado `0x17` (mode+subSence+noiseValue, pendente)
- **EQ**: 0x20/0x22/0x46/0x47 — estruturas capturadas, controle pendente
- **Diferenças entre builds**: 715 é fork health (pedômetro); 682/689 são fone

## Pendências — o que falta fazer

### Alta prioridade
1. Validar 2-3 comandos GATT no hardware real (`0000ae00` / Service `0000A001`)
2. Implementar EQ no `qcy-ctl` (0x20/0x22 — presets + custom 10 bandas)
3. Testar ANC avançado 0x17 (mode/subSence/noiseValue) auditivamente
4. Implementar canal RX no SPP (hoje só TX — não lemos respostas do fone)
5. Criar TUI/GUI minimalista sobre o CLI Bun

### Média prioridade
6. KEYFUN (0x2B) — mapear botões físicos
7. Bateria pela GATT (`00002a06`) em vez de `bluetoothctl`
8. Mapear CMDIDs incompletos: 0x06, 0x0A, 0x11, 0x1E, 0x1F, 0x32, 0x3A, 0x3B, 0x3D, 0x3E, 0x3F, 0x43, 0x45, 0xFE

### Baixa prioridade
9. Perfil EasyEffects DSP (EQ externo sem mexer no firmware)
10. SPACE_AUDIO / ENV_ADAPTATION / INEAR_SENSITIVITY — testar
11. TWS_ENABLE / LED_SWITCH / LED_EFFECT — testar
12. Post-mortem 3 meses do projeto

## Comandos do dia a dia

```bash
./bin/qcy-ctl anc on          # ANC ligado
./bin/qcy-ctl anc off         # ANC desligado
./bin/qcy-ctl anc trans       # Modo transparente
./bin/qcy-ctl volume 70       # Volume L/R
./bin/qcy-ctl game on         # Low latency
./bin/qcy-ctl music next      # Próxima faixa
./bin/qcy-ctl battery         # Bateria
./scripts/qcy-install-mic-setup.sh   # reaplica config do repo → sistema
```

## Limitações conhecidas

- HFP = mono **mSBC ~16 kHz** (fallback CVSD 8 kHz se mSBC falhar).
- QCY não faz duplex A2DP + HFP simultâneo.
- Troca A2DP↔HFP ≈ 1–2 s.
- Cabo Type-C no PC desliga BT; usa stack USB ALSA separado.
- GATT vendor não exposto pelo BlueZ neste device — controle real via SPP.

## Documentação

- **Protocolo completo:** `analysis/QCY-H3S-PROTOCOL-COMPLETO.md`
- **Setup completo:** `docs/MIC-SETUP-FINAL.md`
- **O que não fazer:** `TENTATIVAS-SEM-SUCESSO.md`
- **Kernel/dongle:** `KERNEL-BARROT-PATCH-PLAN.md`