# Estado Atual — QCY H3S no Linux

**Atualizado:** 15/06/2026 (noite)  
**Status:** ✅ Conectado · ✅ Música A2DP/AAC · ✅ Mic OpenWhispr + BrowserOS

## Configuração ativa (não mudar sem ler `docs/MIC-SETUP-FINAL.md`)

| Camada | O quê |
|--------|--------|
| Perfil música | `a2dp-sink` (AAC) |
| Perfil mic | `headset-head-unit` **mSBC 16 kHz** sob demanda (fallback CVSD nos scripts) |
| WirePlumber | `51-qcy-h3s-bt.conf` + `52-qcy-disable-analog-mic.conf` |
| Autoswitch | `bluetooth.autoswitch-to-headset-profile = true` |
| Systemd user | `qcy-mic-default.timer` (60s); watcher **off** — só autoswitch WP |
| BrowserOS | `~/.local/share/browseros/browseros-wrapper.sh` com **X11** |
| OpenWhispr | `preferBuiltInMic=false` no leveldb |
| Kernel | `force_scofix=1` (DKMS btusb Barrot) |

## Comandos do dia a dia

```bash
./scripts/qcy-install-mic-setup.sh   # reaplica config do repo → sistema
./scripts/qcy-apps-ready.sh          # antes de gravar voz
./scripts/qcy-mic-diagnose.sh --record
```

## O que estava quebrado (e a causa real)

1. **Mic “inexistente” em apps** — em A2DP, portal Wayland (`wpctl Sources`) ficava vazio.
2. **BrowserOS** — abria em Wayland; OpenWhispr em X11 (por isso só um funcionava).
3. **OpenWhispr** — `preferBuiltInMic=true` apontava para placa-mãe desabilitada.
4. **HFP fixo** — mic aparecia, mas música ficava em modo telefone o tempo todo (revertido).

## Limitações conhecidas

- HFP = mono **mSBC ~16 kHz** (fallback CVSD 8 kHz se mSBC falhar).
- QCY não faz duplex A2DP + HFP simultâneo.
- Troca A2DP↔HFP ≈ 1–2 s.
- Cabo Type-C no PC desliga BT; usa stack USB ALSA separado.

## Documentação

- **Setup completo:** `docs/MIC-SETUP-FINAL.md`
- **O que não fazer:** `TENTATIVAS-SEM-SUCESSO.md`
- **Kernel/dongle:** `KERNEL-BARROT-PATCH-PLAN.md`