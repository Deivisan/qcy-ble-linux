# QCY BLE Control — Linux CLI

![QCY H3S](docs/images/qcy-h3s-black.jpg) <!-- Adicionar imagem depois -->

Controle total dos fones QCY (H3S e compatíveis) via BLE no Linux, sem depender do app Android.

**Status:** 🧪 **Em desenvolvimento** — Funcionalidade básica implementada, aguardando validação de UUIDs GATT.

---

## 🎯 Objetivo

Substituir o app oficial QCY no desktop, oferecendo:

- **Controle completo** via CLI (ANC, volume, EQ, botões, multipoint, LDAC)
- **Interface GUI** futura (GTK/Qt + web)
- **Suporte multiplataforma** (Linux优先, depois Windows/macOS)
- **Open source** (MIT)

---

## 📦 Stack

- **Runtime:** Bun (CLI-first)
- **Linguagem:** TypeScript
- **BLE Backend:** CLI puro (`gdbus` + `bluetoothctl`) — sem módulos nativos
- **Hardware:** QCY H3S (testado) — compatível com linha QCY TWS usando protocolo **Quicky**

---

## 🚀 Instalação

```bash
# Clonar
git clone https://github.com/deivison santana/qcy-ble-linux.git
cd qcy-ble-linux

# Instalar dependências
bun install

# Compilar (opcional, bun executa .ts diretamente)
bun run build
```

---

## 🔧 Uso

### MAC padrão
```bash
export QCY_BLE_MAC="84:AC:60:05:55:2C"  # Seu MAC
```

### Comandos CLI

```bash
# Bateria
bun run src/cli/ble.ts battery

# Versão firmware
bun run src/cli/ble.ts version

# ANC
bun run src/cli/ble.ts anc on
bun run src/cli/ble.ts anc off
bun run src/cli/ble.ts anc transparency

# Volume (0–100)
bun run src/cli/ble.ts volume 80 80

# Game Mode (low latency)
bun run src/cli/ble.ts latency on
bun run src/cli/ble.ts latency off

# Controle de música
bun run src/cli/ble.ts music play
bun run src/cli/ble.ts music pause
bun run src/cli/ble.ts music next
bun run src/cli/ble.ts music prev
```

---

## 🔍 Protocolo BLE (baseado no Quicky)

O projeto implementa o esquema de mensagens identificado no repositório [Quicky](https://github.com/hui1601/Quicky) (MIT).

### Formato de pacote (0xFF framing)

```
[0xFF] [body_len] [cmd_id] [param_len] [parametros...]
```

### Comandos suportados (parcial)

| Cmd | Nome | Parâmetros |
|-----|------|------------|
| 0x08 | Volume | [left%, right%, 0] |
| 0x09 | Low Latency | [1=on, 2=off] |
| 0x0C | ANC mode | [0=off, 1=ANC, 2=outdoor, 3=transp] |
| 0x17 | ANC avançado | [mode, subScene, noiseValue] |
| 0x04 | Music control | [1=play, 2=pause, 3=next, 4=prev] |

Características GATT (teóricas):

| UUID | Função |
|------|--------|
| `00001001-0000-1000-8000-00805f9b34fb` | Write comandos (com 0xFF) |
| `00001002-0000-1000-8000-00805f9b34fb` | Notify respostas |
| `00000008-0000-1000-8000-00805f9b34fb` | Battery (read direto) |
| `00000007-0000-1000-8000-00805f9b34fb` | Version (read direto) |

⚠️ **Nota:** No dispositivo testado, o serviço principal `0000a001-...` não apareceu no BlueZ. Isso pode indicar UUID diferente (`0000FDF0-...`). A descoberta automática está implementada mas precisa de ajustes.

---

## 🛠️ Arquitetura

```
src/cli/ble.ts    → Interface de linha de comando
src/lib/ble-qcy.ts → Cliente BLE (gdbus wrapper)
analysis/          → Documentação de protocolo
```

```typescript
// Exemplo de uso programático
import { QCYBle } from './src/lib/ble-qcy';

const qcy = new QCYBle();
await qcy.connect('84:AC:60:05:55:2C');
await qcy.setVolume(70, 70);
await qcy.setANCMode(1); // ANC on
await qcy.readBattery();
```

---

## 🐛 Problemas Conhecidos

1. **UUIDs GATT não descobertos** — O BlueZ não lista as characteristics do serviço QCY. Necessário descobrir paths reais manualmente e ajustar `getCharPath()`.
2. **Descobrir service correto** — O log do bluetoothctl mostra `0000FDF0-...` como custom service. Talvez seja esse o UUID real.
3. **Noble com módulo nativo** — Tentado usar `noble`, mas compilação de `bluetooth-hci-socket` falhou. Abordagem atual usa `gdbus` CLI.
4. **Notificações** — Implementação de CCCD + StartNotify ainda não testada.

---

## 📚 Referências

- [Quicky (Go)](https://github.com/hui1601/Quicky) — Implementação de referência
- [BlueZ GATT API](https://git.kernel.org/pub/scm/bluetooth/bluez.git/tree/doc/gatt-api.txt)
- [QCY H3S硬件拆解](https://www.youtube.com/watch?v=...) *(adicione depois)*

---

## 📄 Licença

MIT — veja LICENSE.

---

## 🤝 Contribuindo

1. Fork
2. Crie branch: `git checkout -b feature/nova-funcionalidade`
3. Commit: `git commit -m "feat: adiciona controle de EQ"`
4. Push: `git push origin feature/nova-funcionalidade`
5. Abra PR

**Importante:** Teste com seu fone antes de enviar PR.

---

## 🙏 Agradecimentos

- Equipe Quicky (MIT)
- Comunidade BlueZ
- Testadores com QCY H3S/H3/H4/Minor/...

---

> **AVISO:** Uso por conta própria. Não danifique seus fones. O projeto está em fase alpha.
