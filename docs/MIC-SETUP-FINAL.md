# Microfone QCY H3S — configuração final (funcionando)

**Data:** 15/06/2026  
**Hardware:** QCY H3S `84:AC:60:05:55:2C` + dongle UGREEN Barrot `33fa:0012` (`hci0`)

## Resumo

| Objetivo | Como |
|----------|------|
| Música em **AAC/A2DP** | Perfil padrão `a2dp-sink` + autoswitch WirePlumber |
| Mic ao gravar | **Autoswitch WP** → HFP mSBC 16 kHz (sem watcher) |
| OpenWhispr | Pulse/X11 + `preferBuiltInMic=false` |
| BrowserOS | **Wrapper com `--ozone-platform=x11`** (obrigatório) |

## Por que o fix foi “por aplicativo”?

Não foi capricho — são **APIs de áudio diferentes**:

| App | Plataforma | Enumera mics via | Em A2DP idle |
|-----|------------|------------------|--------------|
| **OpenWhispr** | X11 | Pulse (`pactl` / `bluez_input`) | Vê o QCY |
| **BrowserOS** (antes) | Wayland | Portal KDE (`wpctl Sources`) | Lista **vazia** |
| **BrowserOS** (agora) | X11 (wrapper) | Pulse | Vê o QCY |

O fone e o driver estavam OK; o BrowserOS no Wayland **não listava** o loopback Bluetooth em A2DP.

## Arquivos canônicos (no repositório)

```
config/wireplumber/51-qcy-h3s-bt.conf      # autoswitch A2DP↔HFP, regras QCY
config/wireplumber/52-qcy-disable-analog-mic.conf
config/systemd-user/qcy-mic-*.service|.timer
config/browseros/browseros-wrapper.sh      # --ozone-platform=x11
scripts/qcy-mic-default.sh                 # default bluez_input
scripts/qcy-mic-hfp-watcher.sh             # legado OFF — autoswitch WP faz A2DP↔HFP
scripts/qcy-openwhispr-mic-fix.sh          # preferBuiltInMic=false
scripts/qcy-apps-ready.sh                  # checklist antes de gravar
scripts/qcy-install-mic-setup.sh           # instala tudo de novo
scripts/qcy-mic-diagnose.sh                # diagnóstico L1–L7
```

**Não reativar:** `53-qcy-bt-mic-visible.conf` (loopback duplo quebra autoswitch).

## Instalação / reaplicar após reboot

```bash
./scripts/qcy-install-mic-setup.sh
./scripts/qcy-apps-ready.sh    # antes de OpenWhispr / BrowserOS
```

## Bluetooth vs cabo USB (Type-C)

- **Bluetooth ativo:** mic via **HFP/SCO** (mono, ~8 kHz CVSD com `msbc=false` no Barrot). É o limite do perfil headset, não bug do Linux.
- **Cabo Type-C no PC:** o README do projeto documenta que o cabo **desliga o rádio BT** do fone. Aparece como USB ALSA (`Jieli Technology QCY_H3S`) — outro dispositivo, outra qualidade. O app QCY no telefone usa BLE para ANC/EQ; no PC via cabo isso **não passa pelo nosso stack BT**.
- **H3 Pro (outro modelo):** cabo AUX da QCY **não leva microfone** — no AUX usa-se o mic do dispositivo conectado. O H3S usa Type-C duplo; consulte o manual para áudio+mic em modo wired.

**Sensores / ANC:** controles ANC e EQ via app QCY exigem BT+app. Em modo cabo USB no Linux, trate como headset USB ALSA simples.

## Melhorar qualidade do mic / transcrição

Guia completo: [MIC-QUALITY.md](./MIC-QUALITY.md) — teste mSBC: `./scripts/qcy-mic-quality-test.sh`

## Melhorar qualidade da transcrição (STT)

O mic **funcionar** ≠ texto **perfeito**. Com BT em HFP:

1. **Fale 20–30 cm do mic**, ritmo moderado, evite fim de frase cortado.
2. **OpenWhispr:** idioma **pt-BR**, modelo maior se disponível; `preferBuiltInMic` OFF.
3. **Evite** BrowserOS + OpenWhispr gravando **ao mesmo tempo** (um canal SCO).
4. **Sessões críticas de ditado:** cabo Type-C no PC (USB ALSA, se disponível) → melhor SNR que CVSD.
5. **Não force `msbc=true`** no Barrot — histórico de instabilidade SCO neste dongle.
6. **Pós-processamento:** pontuação manual ou modelo LLM no texto; o gargalo é áudio 8 kHz.

### Teste objetivo de qualidade

```bash
./scripts/qcy-mic-diagnose.sh --record --save ~/qcy-mic-test.txt
```

`absmax` alto + `rms` razoável = captura OK; texto ruim = limite do codec/STT.

## Variáveis de ambiente

| Variável | Padrão | Uso |
|----------|--------|-----|
| `QCY_MIC_ALWAYS_HFP` | `0` | `1` = HFP fixo (mic sempre na lista; música pior) |
| `QCY_A2DP_RESTORE_DELAY` | `12` | Segundos até voltar A2DP após parar de gravar |
| `QCY_DEVICE_MAC` | `84:AC:60:05:55:2C` | MAC do fone |

## Kernel / dongle

```bash
# /etc/modprobe.d/btusb-barrot-qcy.conf
options btusb force_scofix=1
```

DKMS `btusb-barrot` para UGREEN `33fa:0012`.

## Se quebrar de novo

```bash
./scripts/qcy-install-mic-setup.sh
./scripts/qcy-connect-recover.sh
./scripts/qcy-mic-diagnose.sh
```

Ver também `TENTATIVAS-SEM-SUCESSO.md` (o que **não** repetir).