# Estado Atual — QCY H3S no Linux

**Atualizado:** 16/08/2026 (manhã)  
**Status:** ✅ Controle SPP/RFCOMM · ✅ Música A2DP/AAC · ✅ Mic configurado · ✅ Protocolo documentado (72 Cmd IDs)

## O que está funcionando hoje

| Camada | O quê |
|--------|--------|
| Controle fone | `bin/qcy-ctl` via SPP/RFCOMM (ANC, volume, música, game, LDAC) |
| Perfil música | `a2dp-sink` (AAC) |
| Perfil mic | `headset-head-unit` **mSBC 16 kHz** sob demanda (fallback CVSD nos scripts) |
| WirePlumber | `51-qcy-h3s-bt.conf` + `52-qcy-disable-analog-mic.conf` |
| Autoswitch | `bluetooth.autoswitch-to-headset-profile = true` |
| BrowserOS | `~/.local/share/browseros/browseros-wrapper.sh` com **X11** |
| OpenWhispr | `preferBuiltInMic=false` no leveldb |
| Kernel | `force_scofix=1` (DKMS btusb Barrot) |

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