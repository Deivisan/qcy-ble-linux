# 🎧 QCY Control - Guia de Instalação e Uso

Sistema completo de controle para fones **QCY H3S/H2S** no Linux Arch/CachyOS usando **Bun** + **TypeScript**.

## 📦 Requisitos

- Arch Linux / CachyOS (ou derivado)
- Bun 1.3.x
- PipeWire 1.6+ + WirePlumber 0.5+
- BlueZ 5.86+ com flag `-E` (HFP)
- Dispositivo QCY H3S conectado (USB ou Bluetooth)

## 🚀 Instalação Rápida

```bash
# 1. clonar e instalar dependências
bun install

# 2. copiar udev rules (permitir acesso ao device input sem sudo)
sudo cp udev/99-qcy.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger

# 3. adicionar usuário ao grupo 'input' (se usar regra por grupo)
sudo usermod -aG input $USER
# re-login necessário

# 4. testar status
bun run start status

# 5. testar captura de eventos (precisa do fone conectado e device correto)
bun run evtest:real
```

## 🔧 Configuração

Após primeira execução, config será criada em `~/.config/qcy/config.json`.

Personalize conforme necessário:

```json
{
  "device": {
    "mac": "84:AC:60:05:55:2C",
    "evdevPath": "/dev/input/event19"
  },
  "profiles": {
    "default": "a2dp",
    "autoSwitch": true
  },
  "actions": {
    "playPause": "mpris:playpause",
    "nextTrack": "mpris:next",
    "volumeUp": "command:pactl set-sink-volume @DEFAULT_SINK@ +5%"
  },
  "daemon": {
    "enabled": true,
    "debug": false
  }
}
```

## 🎮 Comandos Disponíveis

### CLI

- `bun run start status` — exibe status do dispositivo e perfil ativo
- `bun run profile a2dp|hfp|toggle` — alterna perfil de áudio
- `bun run evtest:real` — captura e exibe eventos dos botões
- `bun run daemon` — inicia daemon de automações (background)

### Profile Switcher

```bash
# para áudio de alta qualidade (sem mic)
bun run profile a2dp

# para chamadas/gravação (com mic)
bun run profile hfp

# alternar automaticamente
bun run profile toggle
```

## 🛠️ Identificando o Device Evdev

1. Conecte o fone (USB ou Bluetooth)
2. Execute evtest e observe qual device mostra eventos ao pressionar botões:

```bash
# listar todos dispositivos input
ls -l /dev/input/by-id/

# testar cada eventX até detectar botões
bun run evtest:real /dev/input/eventX
```

O dispositivo correto geralmente contém "QCY" ou "BT" no nome.

## 🔄 Sistema de Automações (Daemon)

O daemon roda em background escutando eventos e executando ações configuradas:

```bash
# iniciar daemon
bun run daemon &

# parar
pkill -f "bun run daemon"
```

Ações suportadas:

- `mpris:<comando>` — controla player de mídia (playpause, next, previous)
- `command:<shell>` — executa comando no sistema
- `profile:<a2dp|hfp>` — alterna perfil de áudio

## 📡 Status e Diagnóstico

```bash
# pipewire
wpctl status

# bluez (bluetooth)
bluetoothctl info 84:AC:60:05:55:2C

# pactl (pulseaudio compatibility)
pactl list cards short
pactl list sinks short
pactl list sources short

# testar gravação do mic
timeout 5 parecord --device=bluez_input.84:AC:60:05:55:2C /tmp/test.wav && aplay /tmp/test.wav
```

## ⚠️ Troubleshooting

### perfil não altera
verifique se o bluez está com flag `-E`:

```bash
systemctl --user status bluetooth
# deve conter: /usr/lib/bluetooth/bluetoothd -E
```

### evtest:real sem permissão
```bash
# garantir udev rules aplicadas
sudo udevadm control --reload-rules
sudo udevadm trigger

# ou rodar manualmente com sudo
sudo bun run evtest:real
```

### microfone BT mostra silêncio
conforme `qcy-fix.md`, o problema pode ser:
- fone conectado via USB simultaneamente (desconectar USB)
- perfil em A2DP (mudar para headset-head-unit)
- needs re-pair after installing WirePlumber config

### daemon não inicia
verifique se o caminho em `evdevPath` está correto e acessível.

## 💡 Próximas Features

- [ ] GUI web-based para configuração
- [ ] suporte a múltiplos dispositivos
- [ ] perfis por aplicativo
- [ ] mapeamento avançado de botões (triple-click, long-press)
- [ ] integração com systemd user service

## 📚 Referências

- Diagnóstico completo: [qcy-fix.md](./qcy-fix.md)
- PipeWire/BlueZ: `man wpctl`, `man pactl`, `man bluetoothctl`
- Evdev: `/usr/include/linux/input.h`

---

**License:** MIT  
**Author:** Deivison Santana <devsan@deivison.tech>
