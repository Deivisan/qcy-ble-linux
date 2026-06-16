# Qualidade do microfone QCY H3S — o que dá para melhorar

## Limite físico (Bluetooth)

| Modo | Codec | Taxa | Uso |
|------|-------|------|-----|
| Música | AAC/A2DP | 44–48 kHz estéreo | Idle |
| Voz BT (fallback) | **CVSD** | **8 kHz mono** | se mSBC falhar |
| Voz BT (**ativo**) | **mSBC** | **16 kHz mono** | HFP ao gravar (config fixa) |
| Cabo Type-C USB | PCM USB | até 48 kHz | Fone como USB ALSA |

O H3S tem **7 mics + AI para chamadas** no hardware — o gargalo no PC é o **perfil HFP**, não o capsule.

STT (OpenWhispr, BrowserOS/SODA, Whisper) recebe o que o SO entrega. Não “conhece” o modelo do fone.

## Melhorias por impacto

### 1. mSBC wideband (maior ganho em BT)

Com `bluez5.enable-msbc = true`, o QCY expõe:

- `headset-head-unit` → **MSBC** (16 kHz) — preferir este
- `headset-head-unit-cvsd` → CVSD (8 kHz) — fallback

**Estado (Jun/2026):** mSBC **fixo** em `51-qcy-h3s-bt.conf`. Scripts usam `headset-head-unit` (MSBC) com fallback automático para CVSD.

Se picotar/travar SCO:

```bash
./scripts/qcy-mic-quality-test.sh --restore-cvsd
```

### 2. Cabo Type-C no PC (melhor qualidade absoluta)

- Desliga o rádio BT do fone.
- Aparece como `Jieli Technology QCY_H3S` (USB ALSA).
- Use para sessões longas de ditado; BT fica para uso normal.

### 3. Ajustes PipeWire (ganho pequeno, seguro)

No loopback de captura (`bluez_input`):

- `resample.quality = 10` — resampling mais limpo
- `node.latency = 1024/48000` — buffer um pouco maior, menos picote
- Volume do source em **100%** (`pactl set-source-volume`)

### 4. Pós-processamento (depende do app)

| Ferramenta | Efeito |
|----------|--------|
| **RNNoise** (PipeWire filter-chain) | Reduz ruído de fundo; pode ajudar ou atrapalhar STT |
| **EasyEffects** compressor | Nivela volume da voz |
| **Whisper large** no OpenWhispr | Compensa áudio ruim no texto final |

### 5. Hábitos (grátis)

- Fale a **20–30 cm** do mic do fone.
- **Uma app** gravando por vez (um canal SCO).
- Evite ANC máximo se picotar em chamada (teste modo Transparency).
- Pausas claras entre frases — STT em 8 kHz corta finais.

## O que NÃO melhora o mic BT

- Forçar AAC/A2DP durante gravação (mic não funciona em duplex).
- Upsample 8 kHz → 48 kHz no software (não cria banda real).
- HFP fixo permanente (só deixa música ruim o tempo todo).
- Loopback `53-qcy-bt-mic-visible` (quebra autoswitch).

## Referências

- [WirePlumber Bluetooth](https://pipewire.pages.freedesktop.org/wireplumber/daemon/configuration/bluetooth.html) — `bluez5.enable-msbc`, `resample.quality`
- QCY H3S: modo wired = cabo Type-C duplo; app móvel para ANC/EQ via BT