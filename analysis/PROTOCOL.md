# 🔬 Protocolo BLE QCY H3S - Análise de Engenharia Reversa

> **APK:** QCY 4.0.7-689 (com.qcymall.googleearphonesetup)  
> **Data:** 2026-05-31  
> **Status:** Análise estática preliminar concluída.

---

## 📦 Estrutura do SDK

O aplicativo usa o SDK **com.yc.nadalsdk** para comunicação BLE, com classes ofuscadas.

### Classes Principais

| Classe Java |smali path | Função |
|-------------|------------|--------|
| `UteBleClient` | `smali_classes4/com/yc/nadalsdk/ble/open/UteBleClient.smali` | Singleton, inicializa conexão |
| `UteBleDevice` (interface) | `smali_classes4/com/yc/nadalsdk/ble/open/UteBleDevice.smali` | Define operações do dispositivo |
| `UteBleConnection` (interface) | `smali_classes4/com/yc/nadalsdk/ble/open/UteBleConnection.smali` | Define operações de conexão |
| `DeviceModeJX` | `smali_classes4/com/yc/nadalsdk/ble/open/DeviceModeJX.smali` | Bitflags de recursos suportados |

---

## 🕵️ Implementações Ofuscadas

- `UteBleDevice` → `utedo/uteint` (`smali_classes6/utedo/uteint.smali`)
- `UteBleConnection` → `utedo/utefor` (`smali_classes6/utedo/utefor.smali`)  
- Lógica BLE interna → pacotes `utefor/` e `uteif/`

**Cadeia de chamadas para envio:**

```
UteBleConnection.sendDataToJlDevice([B)
  → utedo/utefor.sendDataToJlDevice([B)
    →Luteif/utefor;->utegoto() singleton
      → Lutefor/utegoto;->utedo([B)V
        → Lutedo/uteif;->utefor().utedo([B)V  (escrita GATT real)
```

---

## 🔤 Formato de Pacote ( Hipótese )

Com base no método `Lutefor/utefor;->utedo([B)V` (linha 404 de `smali_classes6/utefor/utefor.smali`:

```smali
aget-byte v0, p1, 2       ; byte 2 (índice 2)
shl-int/lit8 v0, v0, 0x8  ; shift left 8 bits
aget-byte v1, p1, 3       ; byte 3
or-int/2addr v0, v1       ; v0 = (p1[2] << 8) | (p1[3] & 0xff)
const v1, 0xac01
if-eq v0, v1, :cond_0     ; se v0 == 0xAC01, entra no switch
```

- **Opcode** = 2 bytes em offsets 2-3 (big-endian).
- Exemplo: `0xAC01`, `0xAC02`, `0xAC03` detectados no switch.

**Packets de resposta** usam opcodes 0xAC01..03 com byte 4 = 0xFD (checksum?) e byte 5 como CRC.

Para **commandos de envio**, a estrutura pode ser similar, mas métodos como `DeviceModeJX.isHasFunction_X(I)` sugerem que a lógica de recursos usa bitmasks.

---

## 📋 Recursos Suportados (DeviceModeJX)

A classe `DeviceModeJX` define constantes de plataforma e features:

```java
IS_PLATFORM_JLAC701 = 0x4000
IS_PLATFORM_JXATS3085L = 0x8000
IS_PLATFORM_JXATS3085S = 0x10000
IS_SUPPORT_BLOOD_PRESSURE = 0x40000
IS_SUPPORT_CHAT_GPT = 0x200000
IS_SUPPORT_EMOTIONAL = 0x80000
IS_SUPPORT_EPHEMERIS_SERVICE = 0x100
IS_SUPPORT_HEALTH_DATA_EXPANSION = 0x20000
IS_SUPPORT_HID_SERVICE = 0x4000
IS_SUPPORT_LANGUAGE_PACK = 0x10000
IS_SUPPORT_SM_GAME = 0x100000  ; game mode?
IS_SUPPORT_TWO_WAY_SETTINGS = 0x400000
IS_SUPPORT_WORLD_CLOCK = 0x8000
```

Verificação via `SPUtil.getCharacterisicFunctionListX()` (X=1..13) retorna um bitmask de features habilitadas.

---

## 🔧 Sequência de Conexão

1. `UteBleClient.initialize(Context)` → cria singleton.
2. `UteBleClient.connect(mac)` → retorna `UteBleConnection`.
   - Internamente usa `BluetoothDevice.connectGatt(context, false, callback, TRANSPORT_AUTO=2)`.
3. Após conexão GATT, o SDK descobre serviços e characteristics.
4. Notificações são ativadas via `openOrCloseNotify(true)`.

---

## 🎯 Objetivo Final: Comandos para QCY H3S

Queremos controlar:
- ANC on/off
- Modo Transparency
- Equalizador (bass, flat, vocal)
- Game mode
- Configurações de botões
- Status (bateria, conexão)

---

## 🚀 Próximos Passos

### Fase A: Análise Estática Adicional (opcional)
- Mapear classes `com.yc.nadalsdk.bean.*` (DeviceOperatorConfig, DoNotDisturbInfo, etc.)
- Identificar como serializar em bytes.

### Fase B: Análise Dinâmica com Frida (Recomendado)
1. Instalar Frida no Android (frida-server).
2. Usar script que hooka:
   - `Landroid/bluetooth/BluetoothGatt;->writeCharacteristic(...)`
   - `Lcom/yc/nadalsdk/ble/open/UteBleConnection;->sendDataToJlDevice([B)`
   - `Lutefor/utefor;->utedo([B)V`
3. Executar ações no app oficial e capturar os *payloads* enviados.
4. Documentar tabela de comandos.

### Fase C: Implementação em TypeScript
- Criar `src/lib/ble-qcy.ts` com:
  - Classe `QCYCtrl` wrapper sobre Web Bluetooth ou biblioteca Node (noble).
  - Constantes de opcodes e estruturas de pacotes.
  - Métodos `setANC(enabled)`, `setEQ(mode)`, `getBattery()`, etc.
- Integrar com CLI existente: `qcy-control ble anc on`, `qcy-control ble eq bass`.

---

## 📁 Arquivos de Análise

Todos os arquivos descompilados estão em:
```
analysis/apktool/
├── smali_classes4/com/yc/nadalsdk/ble/open/
│   ├── UteBleClient.smali
│   ├── UteBleDevice.smali
│   ├── UteBleConnection.smali
│   └── DeviceModeJX.smali
├── smali_classes6/utedo/uteint.smali        ; implementação UteBleDevice
├── smali_classes6/utedo/utefor.smali        ; implementação UteBleConnection (proxy)
├── smali_classes6/utefor/utefor.smali      ; writer GATT?
├── smali_classes6/uteif/utefor.smali       ; delegador
└── (etc.)
```

---

## 🔗 Referências Úteis

- `qcy-fix.md` — diagnóstico completo do dispositivo no Linux.
- `AGENTS.md` — diretrizes do projeto.
- `README.md` — instruções de uso da CLI atual.

---

**Próximo:** Gerar script Frida e commitar análise no git.