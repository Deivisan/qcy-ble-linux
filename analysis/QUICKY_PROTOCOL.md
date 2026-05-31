# Protocolo BLE QCY - Documentação Completa (baseado no projeto Quicky)

Fonte: https://github.com/hui1601/Quicky (licença MIT)

---

## 📡 Serviços GATT

| UUID | Descrição | Modo |
|------|-----------|------|
| `0000a001-0000-1000-8000-00805f9b34fb` | QCY Main Service | service |
| `00001001-0000-1000-8000-00805f9b34fb` | Command Write (protocolo principal) | write |
| `00001002-0000-1000-8000-00805f9b34fb` | Settings Read / Notify | notify |
| `00000008-0000-1000-8000-00805f9b34fb` | Battery (Leitura direta) | read |
| `00000007-0000-1000-8000-00805f9b34fb` | Version (Leitura direta) | read |
| `0000000B-0000-1000-8000-00805f9b34fb` | EQ (escrita direta) | write |
| `0000000D-0000-1000-8000-00805f9b34fb` | Key Function (mapeamento botões) | read/write |

---

## 🎯 Formato de Pacote

Todos os comandos enviados para `00001001` e respostas recebidas em `00001002` usam este framing:

```
[0xFF] [body_len] [cmd1] [param_len1] [params1...] [cmd2] [param_len2] [params2...] ...
```

- `0xFF` = Start of Frame (signed -1)
- `body_len` = comprimento total do corpo (sem incluir SOF e length)
- Cada comando: `cmd_id` (1 byte) + `param_len` (1 byte) + `params` (N bytes)

**Observação:** EQ (0x0B) e Key Function (0x0D) são escritos **diretamente** sem framing `0xFF`.

---

## 🎛️ Comandos Principais (paraQCY H3S)

### 0x0C — Noise Cancel Mode (ANC/Transparência)

```text
Send: [0x0C, 0x01, mode]
```

| mode | descrição |
|------|-----------|
| 0x00 | Off |
| 0x01 | ANC |
| 0x02 | Outdoor (reduz ruído, menos que ANC) |
| 0x03 | Transparency (transparência) |

**Resposta:** `[0x0C, 0x01, mode]`

**Exemplo CL**: ANC ligado → payload: `FF 03 0C 01 01`

---

### 0x17 — ANC Setting (controle avançado)

```text
Send: [0x17, 0x03, mode, subScene, noiseValue]
```

- `mode` (1 byte): tipo de ANC (0=off, 2=silent environment, 3=working, 4=noisy, 10=transparency)
- `subScene` (1 byte): nível dentro do modo (1-3 para ANC, 1-7 para transparency)
- `noiseValue` (1 byte): valor de profundidade (0-255)

**Exemplo:** ANC nível 2 (modo silent, subScene 2) → `FF 05 17 03 02 02 80` (noiseValue exemplo 0x80)

**Resposta:** `[0x17, 0x03, mode, subScene, noiseValue]`

---

### 0x08 — Volume

```text
Send: [0x08, 0x03, left, right, 0x00]
```

- `left`, `right`: 0-100 (volume %)
- terceiro byte: reservado (0x00)

**Resposta:** `[0x08, 0x03, leftVoice, rightVoice, maxVoice]`

---

### 0x09 — Low Latency (Game Mode)

```text
Send: [0x09, 0x01, state]
```

| state | descrição |
|-------|-----------|
| 0x01 | Enable |
| 0x02 | Disable |

**Resposta:** `[0x09, 0x01, state]`

---

### 0x2F — Battery

```text
Response: [0x2F, 0x03, left, right, case]
```

Cada byte:
- Bit 7 (0x80): carregando (1 = sim)
- Bits 0-6 (0x7F): nível 0-127 (mapeia para %)

---

### 0x30 — Version

```text
Response (3 bytes): [0x30, 0x03, major, minor, patch]
Response (6 bytes): [0x30, 0x06, Lmaj, Lmin, Lpat, Rmaj, Rmin, Rpat]
```

---

### 0x06 — In-Ear Detection

```text
Send: [0x06, 0x01, state]
```

| state | descrição |
|-------|-----------|
| 0x01 | Enable |
| 0x02 | Disable |

---

### 0x2B — Key Function (mapeamento botões)

**Leitura** (característica `0000000D` direto, sem framing):
```
[keyId1, funId1, keyId2, funId2, ...]
```

- `keyId`: IDs de botões (0x01=esq single tap, 0x02=dir single tap, etc.)
- `funId`: função (0x01=play/pause, 0x02=next, 0x03=prev, 0x04=assistente, 0x05/06=volume, etc.)

**Exemplo de escrita:**
```
Write to 0000000D: [0x01, 0x01, 0x02, 0x02, ...]
```

---

### 0xFE — Request Data

Para ler qualquer configuração atual:

```text
Send: [0xFE, 0x01, cmdId]
```

Resposta será no formato do comando `cmdId`.

---

## 🔍 Descoberta de Device (Scan)

Filtrar por **manufacturer data CompanyID `0x521c`** (QCY).

Formato manufacturer data (quando >=20 bytes):

| Offset | Campo | Encoding |
|--------|--------|----------|
| 0-1 | vendorId | big-endian 16-bit |
| 3 | colorIndex | bits 3-4 |
| 5 | leftBattery | bits 0-6 = %, bit7 = charging |
| 6 | rightBattery | idem |
| 7 | caseBattery | idem |
| 11-16 | controlMAC | scrambled order → `[12]:[11]:[13]:[16]:[15]:[14]` |
| 18-23 | otherMAC | scrambled → `[19]:[18]:[20]:[23]:[22]:[21]` |

---

## 🏗️ Implementação em TypeScript

Criar módulo `src/lib/ble-qcy.ts`:

```typescript
export enum QCYCommand {
  ResetDefault = 0x01,
  ClearPairing = 0x02,
  FactoryReset = 0x03,
  MusicControl = 0x04,
  LightFlash = 0x05,
  InEarDetection = 0x06,
  NoiseValue = 0x07,
  Volume = 0x08,
  LowLatency = 0x09,
  Monitoring = 0x0A,
  NoiseCancelMode = 0x0C,
  TestMode = 0x0D,
  SleepMode = 0x10,
  EarTipFitTest = 0x11,
  LedMode = 0x12,
  PowerManager = 0x14,
  SoundBalance = 0x16,
  ANCSetting = 0x17,
  RenameDevice = 0x18,
  VoiceLanguage = 0x19,
  ToneVolume = 0x1D,
  TakePhoto = 0x1E,
  Standby = 0x1F,
  EQParamsV1 = 0x20,
  EQParamsV2 = 0x22,
  LDAC = 0x23,
  AdaptiveEQ = 0x27,
  ANCResult = 0x28,
  ANCwear = 0x29,
  KeyFunction = 0x2B,
  WearingDetection = 0x2C,
  SpatialAudio = 0x2D,
  MusicMode = 0x2E,
  Battery = 0x2F,
  Version = 0x30,
  EnvAdaptation = 0x32,
  TWSEnable = 0x34,
  LEDSwitch = 0x35,
  LEDEffect = 0x36,
  PlayMode = 0x37,
  FocusMode = 0x39,
  MusicStatus = 0x3A,
  MusicInfo = 0x3B,
  TonePlay = 0x3D,
  SyncTime = 0x3E,
  Alarm = 0x3F,
  AI = 0x43,
  MaxEQCount = 0x44,
  CustomEQTest = 0x45,
  EQLeft = 0x46,
  EQRight = 0x47,
  InEarSensitivity = 0x48,
  GameConfig = 0x4A,
  RequestData = 0xFE,
}

export enum ANCSettingMode {
  OFF = 0x00,
  ANC = 0x02,
  OUTDOOR = 0x03,
  TRANSPARENCY = 0x04,
  TRANSPARENCY_LEVEL1 = 0x0A, // or 0x0A-0x10 for levels 1-7
}

// ... implementar cliente
```

---

## 🎯 Próximas Tarefas (urgente)

1. Implementar `src/lib/ble-qcy.ts` com:
   - `connect(mac: string)`
   - `disconnect()`
   - `sendCommand(cmd: QCYCommand, params: number[])`
   - `setANCMode(mode: ANCSettingMode)`
   - `setVolume(left: number, right: number)`
   - `setGameMode(enabled: boolean)`
   - `getBattery()` → Promise<{left: number, right: number, case?: number}>
   - `getVersion()`
   - `onNotification(callback)`

2. Escolher biblioteca BLE para Linux:
   - Opção A: `noble` (Node,Cross-platform) — mais fácil
   - Opção B: BlueZ D-Bus via `@pedroariasalz/bulez` ou wrapper próprio
   - Opção C: usar `bluetoothctl` subprocess (menos eficiente)

3. Integrar com CLI:
   ```bash
   qcy-control ble anc on
   qcy-control ble anc off
   qcy-control ble eq preset <index>
   qcy-control ble battery
   qcy-control ble latency on
   ```

4. Testar no QCY H3S (ou outro modelo com ANC)

---

**Vou implementar AGORA!** 

Preciso só de uma decisão: qual biblioteca BLE? Vou usar **noble** porque é a mais usada e funciona com Node (Bun suporta). Se preferir BlueZ nativo, avise.

Iniciando implementação... 🚀