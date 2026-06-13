# 📄 RELATÓRIO TÉCNICO COMPLETO - FONE QCY H3S

**Data:** 2026-05-12  
**Sistema:** Arch Linux / CachyOS  
**Kernel:** 7.0.5-2-cachyos  
**Dispositivo:** AMD Ryzen 7 5700G

> **Atualização crítica (2026-05-29):** testes anteriores que apenas verificavam existência/tamanho de WAV foram invalidados. A validação correta por sinal (RMS/absmax/nonzero) mostrou casos de silêncio absoluto mesmo com arquivo gerado.

> **Status final (2026-05-29, noite): ✅ RESOLVIDO**
> - Microfone Bluetooth do QCY H3S funcionando em **HFP/HSP com mSBC**.
> - Alternância de perfil (**A2DP ↔ headset-head-unit**) funcionando corretamente.
> - Sem necessidade de script/helper paralelo.

> **Regressão corrigida de verdade (2026-06-05): ✅ RESOLVIDO com validação iterativa**
> - A correção inicial de 2026-06-05 foi específica demais: forçar mSBC podia até criar source e captar por alguns segundos, mas voltava a quebrar transporte (`Failure in Bluetooth audio transport`, `SEP in bad state`, `NotAuthorized`) e/ou cair em silêncio.
> - A causa raiz operacional é a combinação **QCY H3S + UGREEN BT6 + kernel 7.0.x + BlueZ/PipeWire**: depois de restart/reconnect o primeiro transporte HFP pode subir mudo, e mSBC é instável neste adaptador. Não basta verificar que o source existe; precisa gravar e medir sinal.
> - Fix persistente atual: `/etc/wireplumber/wireplumber.conf.d/50-bt-hfp-fix.conf` com `bluez5.enable-msbc = false`, `bluez5.hw-offload-sco = false`, roles completas `[ a2dp_sink a2dp_source hsp_hs hfp_hf hfp_ag ]`, `device.profile = "headset-head-unit"` e persistent storage desativado para não ressuscitar estado ruim.
> - Removi/desativei config conflitante de usuário em `~/.config/wireplumber/wireplumber.conf.d/50-bluetooth.conf`.
> - Criei `scripts/qcy-mic-recover.sh`: ele reescreve a config, reinicia stack, reconecta, arma HFP, faz warmup, grava WAV e só aprova se `rms/absmax/nonzero` forem reais. Se CVSD falhar, tenta mSBC automaticamente.
> - Validação final do recuperador: `/tmp/qcy-cvsd.wav` com `rms=10.785`, `absmax=976`, `nonzero=74252/671744` — microfone realmente captando.

---

## 📱 IDENTIFICAÇÃO DO DISPOSITIVO

```yaml
Fabricante: Jieli Technology
Produto: QCY H3S
ID USB: 3654:4a55
Caminho USB: Bus 001 Device 023
Nome do Dispositivo: QCY H3S
Nome Longo (USB): Jieli Technology QCY H3S at usb-0000:02:00.0-1, full speed
```

---

## 🔊 DRIVERS E VERSÕES

| Componente | Versão | Status |
|------------|--------|--------|
| **Kernel ALSA** | snd_usb_audio | ✅ Carregado |
| **PipeWire** | 1.6.4 | ✅ Ativo |
| **PipeWire-ALSA** | 1.6.4 | ✅ Ativo |
| **WirePlumber** | 0.5 | ✅ Ativo |
| **BlueZ** | 5.86 | ✅ Ativo (com flag -E) |
| **ALSA-ucm-conf** | 1.2.15.3 | ✅ Ativo |

---

## 🎧 SAÍDA DE ÁUDIO (FONE VIA USB)

```yaml
Sink Name: alsa_output.usb-Jieli_Technology_QCY_H3S_433132373431352E-00.analog-stereo
Descrição: QCY H3S Estéreo analógico
Driver: PipeWire
Especificação: s24le 2ch 48000Hz
Mapa de Canais: front-left, front-right
Mute: false
Volume: 100% (0.00 dB)
Base Volume: 104% (0.94 dB)
Perfil Ativo: output:analog-stereo+input:mono-fallback
```

---

## 🎙️ ENTRADA DE ÁUDIO (MICROFONE VIA USB) ✅ FUNCIONANDO

```yaml
Source Name: alsa_input.usb-Jieli_Technology_QCY_H3S_433132373431352E-00.mono-fallback
Descrição: QCY H3S Mono
Driver: PipeWire
Especificação: s16le 1ch 48000Hz
Mapa de Canais: mono
Mute: false
Volume: 100% (0.00 dB)
Base Volume: 104% (0.94 dB)
Perfil Ativo: output:analog-stereo+input:mono-fallback
```

---

## 🔧 CONFIGURAÇÕES TÉCNICAS

### Resoluções de Áudio
- **Saída:** s24le 2ch 48000Hz (24-bit, 2 canais, 48kHz)
- **Entrada:** s16le 1ch 48000Hz (16-bit, 1 canal, 48kHz)

### Capacidades
- ✅ Hardware volume control
- ✅ Hardware mute control
- ✅ Decibel volume
- ✅ Latency support

---

## 🆚 BLUETOOTH vs USB

| Recurso | Bluetooth | USB |
|---------|-----------|-----|
| **Áudio (A2DP)** | ✅ AAC 48kHz | ✅ s24le 48kHz |
| **Microfone** | ❌ CSR dongle não suporta HFP | ✅ s16le mono 48kHz |
| **Qualidade áudio** | Alta (AAC) | Alta (PCM) |
| **Requisito** | Dongle Bluetooth CSR | Cabo USB |

---

## 🔧 CORREÇÕES APLICADAS NESTE PC

### 1. Dongle Bluetooth CSR — USB autosuspend
**Problema:** Dongle CSR clone desconectando do USB por power saving.
**Solução:** Regra udev em `/etc/udev/rules.d/50-csr-bt-dongle-fix.rules`:
```
ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="0a12", ATTRS{idProduct}=="0001", ATTR{power/control}="on"
```

### 2. Bluetoothd sem flag experimental
**Problema:** HFP (Hands-Free Profile) não funciona sem `-E`.
**Solução:** Override systemd em `/etc/systemd/system/bluetooth.service.d/override.conf`:
```
[Service]
ExecStart=
ExecStart=/usr/lib/bluetooth/bluetoothd -E
```

### 3. WirePlumber com config Lua antiga
**Problema:** WP 0.5 não suporta mais arquivos `.lua`.
**Solução:** Config nativa aplicada em `/etc/wireplumber/wireplumber.conf.d/50-bt-hfp-fix.conf` com política de headset ativa:
```
monitor.bluez.properties = {
  bluez5.enable-msbc = true
  bluez5.enable-sbc-xq = true
  bluez5.hfphsp-backend = "native"
  bluez5.hw-offload-sco = false
  bluez5.roles = [ a2dp_sink a2dp_source hsp_hs hfp_hf hfp_ag ]
}

monitor.bluez.rules = [
  {
    matches = [ { device.name = "bluez_card.84_AC_60_05_55_2C" } ]
    actions = {
      update-props = {
        bluez5.auto-connect = [ hfp_hf ]
        device.profile = "headset-head-unit"
      }
    }
  }
]

wireplumber.settings = {
  bluetooth.use-persistent-storage = true
  bluetooth.autoswitch-to-headset-profile = true
}
```

### 4. BrowserOS sem acesso ao microfone
**Problema:** AppImage não herda variáveis PipeWire/PulseAudio.
**Solução:** Wrapper modificado em `/home/deivi/.local/share/browseros/browseros-wrapper.sh`:
```bash
export PULSE_SERVER="unix:/run/user/$(id -u)/pulse/native"
export PIPEWIRE_REMOTE="/run/user/$(id -u)/pipewire-0"
```

---

## 🧪 AÇÕES EXECUTADAS (2026-05-29) — Reinstalação completa do stack áudio/Bluetooth

- Backup das configs: `/etc/pipewire`, `/etc/wireplumber`, `/etc/bluetooth`, `/etc/pulse` → salvo em: `/home/deivi/backup-audio-20260529_185950`
- Reinstalei/atualizei os pacotes (pacman -Syu):
  - pipewire, pipewire-pulse, pipewire-alsa, pipewire-jack, wireplumber
  - bluez, bluez-utils, bluez-tools
  - alsa-utils, pulseaudio-alsa
  - ofono (não disponível/no-repo — ignorado)
- Reiniciei serviços: `systemctl --user restart pipewire pipewire-pulse wireplumber` e `sudo systemctl restart bluetooth`.

Resultados dos testes imediatos:

- Conexão Bluetooth com QCY: por vezes `br-connection-busy` impede reconexão (se o fone estiver ligado/ocupado por USB). Verifique se o fone NÃO está conectado via cabo USB quando for testar Bluetooth.
- Perfil A2DP era padrão (boa reprodução, sem microfone). Forçando perfil HFP/HSP (`pactl set-card-profile bluez_card.84_AC_60_05_55_2C headset-head-unit`) o dispositivo expõe entrada `bluez_input.84:AC:60:05:55:2C`.
- Gravações de teste do Bluetooth mic: `test_qcy_mic.wav`, `test_default_bt_mic.wav` e `test_qcy_native_hfp.wav` **foram geradas, mas a análise de sinal mostrou silêncio absoluto** (`absmax=0`, `rms=0`, `nonzero=0`).
- O serviço helper foi removido; o sistema agora depende apenas do WirePlumber nativo para alternar perfil quando necessário.

Validação final após correção de baixo nível:

- Perfil ativo após reconnect sem forçar continuamente: `headset-head-unit` (mSBC disponível e ativo).
- Captura com sinal real em BT mic (`test_qcy_after_rule.wav`):
  - `absmax=21`
  - `rms=0.678`
  - `nonzero=8032/229376`
- Resultado prático confirmado em uso manual: microfone funcionando e troca de perfil correta.

Logs e sinais importantes:

- `journalctl -u bluetooth` mostra mensagens sobre endpoints A2DP registrados e, ocasionalmente, `Unable to get Hands-Free Voice gateway SDP record: Host is down` quando o lado remoto não responde ou a conexão falha.
- `pwctl status` e `pactl list cards` mostram o card `bluez_card.84_AC_60_05_55_2C` com perfis `a2dp-sink` (ativo por padrão) e `headset-head-unit` (HFP) disponíveis.

Estado operacional recomendado:

1. Manter o QCY desconectado do USB durante uso BT (evita conflito de modo).
2. Manter config nativa do WirePlumber como fonte de verdade (sem scripts auxiliares).
3. Em caso de regressão rara, coletar logs por 1 minuto durante o teste de mic e validar por RMS/nonzero.

Observação: mantive backup das configs em `/home/deivi/backup-audio-20260529_185950` antes da reinstalação — podemos restaurar se algo piorar.

---

## ✅ Estado Atual (resumido)

- Stack: PipeWire 1.6.6 + WirePlumber 0.5.x + BlueZ 5.86 — reinstalados
- Resultado: reprodução (A2DP) OK + microfone BT OK em HFP/HSP (**mSBC funcional**). Autoswitch de perfil está estável.

## 🧠 Diagnóstico final atualizado (2026-05-29)

- **Não é problema da placa-mãe**: o ALSA da motherboard (ALC887 / card 2) foi detectado e o microfone interno grava normalmente.
- **O problema principal era Bluetooth + perfil de headset**: o QCY H3S ficava em `a2dp-sink` (som bom, sem mic) e precisava subir para `headset-head-unit` (HFP/HSP) para o microfone aparecer.
- **Causa secundária**: os helpers paralelos criavam confusão. Eles foram removidos para deixar a gestão só com o WirePlumber.
- **Correção ativa agora**: `bluetooth.autoswitch-to-headset-profile = true` + `bluez5.hw-offload-sco = false` + regra por dispositivo para iniciar em `headset-head-unit`.
- **Prova técnica atualizada**:
  - Antes do ajuste de baixo nível: WAVs com silêncio absoluto (`absmax=0`, `rms=0`, `nonzero=0`).
  - Após ajuste e re-pair: captura com sinal não-zero (`test_qcy_after_rule.wav`: `absmax=21`, `rms=0.678`, `nonzero=8032/229376`), confirmando fim do silêncio absoluto.
- **Validação funcional final**: mSBC ativo e troca automática de perfil funcionando corretamente em uso real.
- **Servidor de áudio em uso**: PipeWire com camada Pulse (`Server Name: PulseAudio (on PipeWire 1.6.6)`), não PulseAudio puro.

---

---

## 📋 COMANDOS ÚTEIS PARA DIAGNÓSTICO

```bash
# Verificar sinks (saídas)
pactl list sinks short

# Verificar sources (entradas/microfones)
pactl list sources short

# Verificar detalhes do QCY USB
pactl list sources | grep -A 30 "QCY H3S Mono"

# Testar captura de áudio USB
arecord -D hw:3 -f S16_LE -r 48000 -c 1 test.wav

# Testar captura via PipeWire
parecord --device=alsa_input.usb-Jieli_Technology_QCY_H3S_433132373431352E-00.mono-fallback test.wav

# Verificar status wireplumber
wpctl status

# Verificar perfil ativo da placa
pactl list cards | grep -A 5 "alsa_card.usb-Jieli"

# Verificar dongle Bluetooth
lsusb | grep -i "0a12\|csr\|bluetooth"
dmesg | grep -i "csr\|bluetooth"
```

---

## ⚠️ NOTA SOBRE O DONGLE BLUETOOTH CSR

O dongle Bluetooth `Cambridge Silicon Radio (0a12:0001)` é um **clone genérico** que o kernel detecta como:
```
CSR: Unbranded CSR clone detected; adding workarounds
```

Este hardware **não suporta HFP (Hands-Free Profile) no Linux** de forma confiável. O erro é:
```
spa.bluez5.native: connect(): Conexão recusada
```

**Solução permanente:** Substituir por um adaptador Bluetooth de qualidade:
- **TP-Link UB500** (chip Realtek, ~R$40)
- **Intel AX200/AX210** (PCIe, melhor opção)
- Qualquer dongle **que não seja CSR**

Enquanto isso, o **cabo USB** funciona perfeitamente com áudio + microfone.

---

## 🛠️ Playbook de recuperação rápida (3 comandos)

Use este bloco quando o mic BT parar de captar ou o perfil travar em A2DP:

### Método atual recomendado (valida sinal real)

```bash
scripts/qcy-mic-recover.sh
```

Esse script não confia em UI nem em existência do source. Ele testa gravação real e falha se `rms`, `absmax` e `nonzero` indicarem silêncio.

### Método manual legado

```bash
# 1) Reinicia stack de áudio e Bluetooth
systemctl --user restart pipewire pipewire-pulse wireplumber && sudo systemctl restart bluetooth

# 2) Reconnect limpo do QCY
bluetoothctl disconnect 84:AC:60:05:55:2C; bluetoothctl connect 84:AC:60:05:55:2C

# 3) Validação rápida de perfil + captura
pactl list cards | sed -n '/Name: bluez_card.84_AC_60_05_55_2C/,+45p' | grep 'Active Profile'; timeout 7 parecord --device=bluez_input.84:AC:60:05:55:2C /tmp/qcy-check.wav
```

Critérios de sucesso:

- `Active Profile: headset-head-unit` durante uso de microfone.
- Arquivo `/tmp/qcy-check.wav` com sinal não-zero (não basta só existir).

Se falhar:

- Garanta que o fone **não está no cabo USB** enquanto testa BT.
- Faça re-pair: `bluetoothctl remove 84:AC:60:05:55:2C` + `pair/trust/connect`.
- Limpe estado do WirePlumber: `rm -rf ~/.local/state/wireplumber` e reinicie `wireplumber`.

---

## 🔬 Pesquisa aprofundada: Bluetooth "6.0" no Linux (real vs marketing)

### O que foi confirmado no host atual

- `btmgmt info` reporta **HCI version 14** no adaptador (`hci0`).
- No Linux, quem define recursos efetivos é o conjunto: **kernel + firmware + BlueZ + PipeWire/WirePlumber + capabilities do fone**.
- Mesmo quando o produto é anunciado como "BT 6.0", recursos de áudio usados hoje no desktop ainda são majoritariamente:
  - **A2DP/AVRCP (BR/EDR)** para música/controles.
  - **HFP/HSP (mSBC/CVSD)** para microfone em chamada.

### Implicação prática para o QCY H3S

- No seu cenário, o fluxo que estabilizou foi BR/EDR clássico com:
  - A2DP para reprodução.
  - HFP/HSP (mSBC) para mic.
- LE Audio/LC3 no desktop Linux ainda pode depender de maturidade de stack/firmware e não é o caminho principal para este caso hoje.

---

## 🎛️ Controle de botões do fone no Linux (AVRCP)

### Estado atual no seu PC

Foi detectado dispositivo de entrada AVRCP ativo:

- `QCY H3S (AVRCP)`
- handler: `event19`

Isso significa que **há caminho para automação por eventos de botão** no Linux.

### O que dá para fazer bem

1. Usar botões do fone para Play/Pause, Next, Prev e Volume via AVRCP/MPRIS.
2. Mapear teclas multimídia para comandos customizados no ambiente gráfico.
3. Criar automações por evento (script/daemon) quando uma tecla AVRCP chegar.

### Limites importantes (triple-click etc.)

- Em muitos fones, o padrão de 1/2/3 cliques é **decidido no firmware do próprio fone**.
- O Linux normalmente recebe o **evento já traduzido** (ex.: `KEY_NEXTSONG`), não a contagem bruta de cliques.
- Então:
  - ✅ dá para remapear o **evento recebido**;
  - ⚠️ triple-click custom só é possível se:
    - o fone expor eventos distintos para isso, **ou**
    - você implementar heurística temporal (ex.: 3 eventos iguais em janela curta).

### Ferramentas úteis

- `evtest /dev/input/event19` → validar quais códigos chegam ao apertar botões.
- `mpris-proxy` + `playerctl` → ponte AVRCP ↔ players MPRIS.
- keybind daemon (KDE/GNOME/keyd/sxhkd/interception-tools) → executar comandos personalizados.

---

## 🧪 Sobre "app QCY para Linux" (viabilidade)

### É possível?

**Sim, mas é projeto de engenharia reversa.**

Como não há app oficial da QCY para Linux, seria necessário:

1. Capturar tráfego BLE entre app Android e fone (GATT/commands).
2. Identificar características, autenticação e formato de payload.
3. Implementar cliente Linux (CLI/GUI) para enviar comandos equivalentes.

### Nível de dificuldade

- **Médio/alto** (protocolos proprietários, possível ofuscação e mudanças por firmware).
- Para uso diário, o caminho mais estável costuma ser:
  - ajustar o que já é padrão (AVRCP/MPRIS/input events), e
  - evitar depender de funções proprietárias do app móvel.

### Via Bluetooth vs cabo

- **Bluetooth:** permite controles de mídia e chamadas (A2DP/HFP/AVRCP), com potencial de automação no Linux.
- **Cabo USB/analógico:** geralmente reduz recursos de controle remoto e tende a expor só áudio/mic.
