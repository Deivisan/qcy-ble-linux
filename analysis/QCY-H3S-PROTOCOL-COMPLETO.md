# 🔬 Protocolo QCY H3S — Documentação Completa

**Fonte:** Engenharia reversa dos APKs QCY 4.0.7 (builds **682**, **689**, **715**)
**Data da análise:** 2026-08-16
**Hardware-alvo:** QCY H3S (`84:AC:60:05:55:2C`) + Dongle UGREEN Barrot

---

## 1. Transporte — Como falar com o fone

O QCY H3S expõe **dois caminhos** para controle:

| Caminho | UUID | Status | Uso |
|---------|------|--------|-----|
| **SPP/RFCOMM** | `00001101-0000-1000-8000-00805f9b34fb` | ✅ Funcionando | Canal principal (`bin/qcy-spp-raw`) |
| **GATT Write** | Service `0000A001-...`<br>Char. `0000ae00-...` | ⚠️ Identificado, não testado no hardware | Fallback quando SPP indisponível |

> O app oficial usa ambos. No Linux, o GATT vendor **não é exposto** pelo BlueZ neste device — por isso o repo foca em SPP/RFCOMM.

---

## 2. Formato de pacote (wire)

```
0xFF  <length>  <cmdID>  <param_count>  [params...]
```

| Campo | Tamanho | Descrição |
|-------|---------|-----------|
| `0xFF` | 1 byte | SOF (Start of Frame) — `DataAnalyse.SOF = 0xFF` |
| `length` | 1 byte | Tamanho total do pacote |
| `cmdID` | 1 byte | Identificador do comando (tabela abaixo) |
| `param_count` | 1 byte | Quantidade de bytes de parâmetro |
| `params` | variável | Parâmetros específicos do comando |

**Leitura de resposta** (`DataAnalyse.analyseAllCMD`):
- Requer `len >= 4`
- `length_byte` no índice 1 deve satisfazer `total_len == length_byte + 2`
- CmdID no índice 2, seguido de `param_count` no índice 3
- Suporta múltiplos comandos concatenados no mesmo frame

---

## 3. Tabela completa de Cmd IDs

Extraída de `DataBean.smali` (`com/qcymall/qcylibrary/dataBean/DataBean`).

### Controle de áudio
| Cmd | Nome | Formato | Notas |
|-----|------|---------|-------|
| `0x04` | `MUSICACTION` | `[0x04 0x01 action]` | 1=play, 2=pause/off, 3=prev, 4=next |
| `0x08` | `VOICE`/volume | `[0x08 0x03 L R 0x00]` | L/R = 0..100+ |
| `0x1D` | `TONEVOLUME` | `[0x1D 0x01 vol]` | volume do tom de notificação |
| `0x23` | `LDAC` | `[0x23 0x01\|0x00]` | ⚠️ ON reinicia o fone |
| `0x2D` | `SPACE_AUDIO` | `[0x2D ...]` | áudio espacial/head-tracking |

### ANC / Noise
| Cmd | Nome | Formato | Notas |
|-----|------|---------|-------|
| `0x07` | `NOISE` | `[0x07 0x01 mode]` | ruído genérico |
| `0x0C` | `NOISEMODE` | `[0x0C 0x01 mode]` | **ANC básico (SPP)** — 0=off, 1=on, 3=out, 4=trans |
| `0x17` | `ANCSETTING` | `[0x17 0x03 mode subSence noiseValue]` | **ANC avançado (GATT)** — 3 parâmetros |
| `0x28` | `ANC_RESULT` | leitura | status ANC |
| `0x29` | `ANC_WEAR` | leitura | detecção de uso |
| `0x32` | `ENV_ADAPTATION` | `[0x32 ...]` | adaptação ao ambiente (vento etc) |
| `0x48` | `INEAR_SENSITIVITY` | `[0x48 ...]` | sensibilidade intra-auricular |

### Modos / Features
| Cmd | Nome | Formato | Notas |
|-----|------|---------|-------|
| `0x09` | `DIYANSHI` | `[0x09 0x01\|0x02]` | game/low-latency (1=on, 2=off) |
| `0x27` | `AEQ` | `[0x27 ...]` | EQ adaptativo |
| `0x39` | `FOCUS_MODE` | `[0x39 ...]` | modo foco |
| `0x2E` | `MUSIC_MODE` | `[0x2E ...]` | modo música |
| `0x37` | `PLAY_MODE` | `[0x37 ...]` | modo playback |
| `0x10` | `SLEEPMODE` | `[0x10 0x01 0x01\|0x00]` | 1=dormir, 0=acordar |
| `0x1F` | `STANDBY` | `[0x1F ...]` | standby |

### EQ
| Cmd | Nome | Formato | Notas |
|-----|------|---------|-------|
| `0x20` | `MULTIEQ` | `[0x20 eqType eqData...]` | EQ multi-banda (10/12 bandas) |
| `0x22` | `MULTIEQ2` | `[0x22 eqType eqData...]` | variante v2 |
| `0x44` | `MAXEQ_COUNT` | leitura | número máx de presets EQ |
| `0x45` | `CUSTOM_EQ_TEST` | `[0x45 ...]` | testar EQ customizado |
| `0x46` | `MULTIEQ_LEFT` | `[0x46 ...]` | EQ do lado esquerdo |
| `0x47` | `MULTIEQ_RIGHT` | `[0x47 ...]` | EQ do lado direito |

### Bateria / Info
| Cmd | Nome | Formato | Notas |
|-----|------|---------|-------|
| `0x2F` | `BATTERY` | leitura | 3 slots: L/R/case |
| `0x30` | `VERSION` | leitura | firmware |
| `0x3A` | `MUSIC_STATE` | leitura | estado da música |
| `0x3B` | `MUSIC_INFO` | leitura | metadata da música |
| `0x18` | `PAIRNAME` | `[0x18 ...]` | nome do pareamento |
| `0x19` | `VOICENAME` | `[0x19 ...]` | idioma/nome da voz |

### Sistema / Config
| Cmd | Nome | Formato | Notas |
|-----|------|---------|-------|
| `0x01` | `RESET_DEFAULT` | `[0x01 0x00]` | reset padrão |
| `0x02` | `CLEAR_PAIR` | `[0x02 0x00]` | apagar pareamento |
| `0x03` | `FACTORY_RESET` | `[0x03 0x00]` | reset de fábrica |
| `0x05` | `LIGHT` | `[0x05 0x01 0x01\|0x00]` | lanterna |
| `0x0A` | `JIANTING` | `[0x0A ...]` | monitor/escuta |
| `0x0D` | `TESTMODE` | `[0x0D ...]` | modo teste (fábrica) |
| `0x11` | `COMPACTNESS` | `[0x11 ...]` | vedação |
| `0x12` | `LEDMODE` | `[0x12 0x01 0x01\|0x00]` | 1=on, 2=off |
| `0x14` | `POWERMANAGER` | `[0x14 ...]` | gerenciamento de energia |
| `0x16` | `BALANCE` | `[0x16 0x01 balance]` | balanceamento L/R |
| `0x1E` | `TAKEPHOTO` | `[0x1E ...]` | shutter remoto |
| `0x2B` | `KEYFUN` | `[0x2B keyID funcID...]` | mapeamento de botões |
| `0x2C` | `PEIDAI` | `[0x2C ...]` | (matching/emparelhamento?) |
| `0x34` | `TWS_ENABLE` | `[0x34 ...]` | TWS on/off |
| `0x35` | `LED_SWITCH` | `[0x35 ...]` | switch LED |
| `0x36` | `LED_EFFECT` | `[0x36 ...]` | efeito LED |
| `0x3D` | `TONE_PLAY` | `[0x3D ...]` | tocar tom de teste |
| `0x3E` | `SYNC_TIME` | `[0x3E ...]` | sincronizar relógio |
| `0x3F` | `ALARM` | `[0x3F ...]` | alarmes |
| `0x43` | `AI` | `[0x43 ...]` | recursos de IA |
| `0xFE` | `REQUESTDATA` | `[0xFE 0x01 cmdID]` | solicitar leitura de cmdID |

---

## 4. Manejo de ANC em detalhe

### Rota SPP (básico, 1 byte de parâmetro)
```bash
./bin/qcy-ctl anc on      # 0x0C 0x01  → modo "on"
./bin/qcy-ctl anc off     # 0x0C 0x00  → modo "off"
./bin/qcy-ctl anc out     # 0x0C 0x03  → modo "out/aware"
./bin/qcy-ctl anc trans   # 0x0C 0x04  → modo "transparency"
```

### Rota GATT (avançado, 3 parâmetros)
```c
// ANCSettingDataBean.getANCSettingCMD(mode, subSence, noiseValue)
0x17 0x03 <mode> <subSence> <noiseValue>
```
- `mode` (byte 2): 0=off, 1=on, 2=transparency... (validar no hardware)
- `subSence` (byte 3): sub-cena (validar faixa)
- `noiseValue` (byte 4): nível de ANC 0..100 (UI do app usa sliders percentuais)

**Resposta de leitura** (setReceiveData):
```
[0] = mode
[1] = subSence
[2] = noiseValue
```

---

## 5. Formatos de resposta (leitura)

### Bateria — `BatteryDataBean` (0x2F)
```
[L_byte | R_byte | Case_byte]
```
- bit `0x80` de cada byte = carregando
- bits `0x7f` = percentual

### Volume — `VolumeDataBean` (0x08)
```
[L | R | max]
```
resposta de 3 bytes: esquerda, direita, máximo.

### EQ — `EQDataBean` (0x20/0x22)
```
[eqType | eqData(10 ou 12 bytes)]
```
- índice 0: `eqType` (preset: 0=, 1=..., 0x80-0xFE = usuário)
- índices 1..10/12: ganhos
- se 12 bytes: `[11]=gameEQType`, `[12]=currentMode`
- ganho na UI = `eqData[i] * 10` (via getUuidString)

### keyFun — `KeyFuncDataBean` (0x2B)
```
[keyID funcID] [keyID funcID] ...
```
pares 2 bytes.

### SingleDataBean (comandos de leitura com retorno 1-2 bytes)
- 1 byte: `value = byte[0]`
- 2 bytes: `value = byte[0] | (byte[1] << 8)` (little-endian)

---

## 6. UUIDs GATT mapeados

Fonte: `uteif/uteif.smali` (classes ofuscadas do SDK Nadal).

### Serviços
| UUID | Significado |
|------|-------------|
| `0000A001-0000-1000-8000-00805f9b34fb` | Service principal (SERVICE_UUID no `BLERequest`) |
| `0000fef5-...` | custom (uteelse) |
| `8082caa8-41a6-4021-91c6-56f9b954cc34` | custom (utegoto) |
| `6c53db25-47a1-45fe-a022-7c92fb334fd4` | custom (utethis) |
| `9d84b9a3-000c-49d8-9183-855b673fda31` | custom (utevoid) |
| `457871e8-d516-4ca1-9116-57d0b17b9cb2` | custom (utebreak) |
| `5f78df94-798c-46f5-990a-b3eb6a065c88` | custom (utecatch) |
| `00006287-3c17-d293-8e48-14fe2e4da212` | custom (uteclass) |
| `0000d0ff-3c17-d293-8e48-14fe2e4da212` | custom (utesuper) |
| `0000ffd3-...` | custom (utethrow) |

### Characteristics de escrita/controle
| UUID | Nome interno | Uso |
|------|-------------|-----|
| `0000ae00-0000-1000-8000-00805F9B34FB` | `utechar` | **principal de escrita** |
| `0000ae01-...` | `utenew` | escrita v2 |
| `0000ae02-...` | `utetry` | escrita v3 / Jieli RCSP |
| `000055ff-...` | `utebyte` | escrita alternativa |
| `000056ff-...` | `utecase` | escrita alternativa 2 |
| `000034f1-...` | `utefor` | config |
| `000034f2-...` | `uteint` | config int |
| `000035f1-...` | `utedo` | config |
| `000035f2-...` | `uteif` | config |
| `00002a06-...` | `utefloat` | Battery Level (padrão) |
| `00002a37-...` | `uteshort` | Heart Rate (padrão) |
| `e49a25e0-f69a-11e8-8eb2-f2801f1b9fd1` | Jieli RCSP | protocolo Jieli (v689+) |
| `e49a28e1-f69a-11e8-8eb2-f2801f1b9fd1` | Jieli RCSP | protocolo Jieli (v689+) |

### Descriptors
| UUID | Significado |
|------|-------------|
| `00002902-...` | CCCD — habilita notificação (`uteconst`) |
| `00002903-...` | CEPD (`utefinal`) |

---

## 7. Diferenças entre builds do APK

| Aspecto | 682 | 689 | 715 |
|---------|-----|-----|-----|
| SDK base | `com/yc/nadalsdk` | `com/yc/nadalsdk` | `com/yc/pedometer` (fork health) |
| classes BLE | smali_classes5 | smali_classes6 | smali_classes6 |
| `uteif/utefor.smali` | idêntico | idêntico | idêntico |
| `utedo/uteint.smali` | 20786 B | 21353 B | 21527 B |
| `utenew/utenew.smali` | LZ4 + 2 logs | LZ4 + 1 log | LZ4 + 1 log |
| foco | fone | fone | fone + smartwatch |

Todos os 3 builds usam **LZ4 compression** (`LZ4Factory.fastCompressor().compress()`) nos pacotes grandes — relevante para OTA e dados longos, não para comandos curtos de controle.

---

## 8. Porte do protocolo para o Linux

### Já implementado (repo)
| Funcionalidade | Comando |
|----------------|---------|
| ANC on/off/out/trans | `./bin/qcy-ctl anc off\|on\|out\|trans` |
| Volume L/R | `./bin/qcy-ctl volume <L> [R]` |
| Game/Low-latency | `./bin/qcy-ctl game on\|off` |
| LDAC | `./bin/qcy-ctl ldac on\|off` |
| Music control | `./bin/qcy-ctl music play\|pause\|next\|prev` |
| Bateria | `./bin/qcy-ctl battery` |
| Raw | `./bin/qcy-ctl raw <cmd> [params...]` |

### Pendente (próximas iterações)
1. **EQ completo** — presets + custom 10/12 bandas (cmd 0x20/0x22/0x46/0x47)
2. **ANC avançado** — 0x17 com subSence + noiseValue, validar no hardware
3. **Leitura de respostas** — implementar RX no canal SPP (atualmente só TX)
4. **KEYFUN** — mapear botões (0x2B)
5. **Bateria pela GATT** — usar char `00002a06` em vez de `bluetoothctl`
6. **SPACE_AUDIO / FOCUS_MODE / ENV_ADAPTATION** — testar
7. **TUI/GUI** — front-end para o CLI Bun existente
8. **Perfil EasyEffects** — EQ externo via DSP (sem tocar no firmware)