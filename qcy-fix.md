# QCY H3S — Linux Control Notes (atualizado 2026-06-14)

## Fatos confirmados

- **Cabo USB desliga o rádio Bluetooth interno** do fone (3654:4a55 VID/PID). Sem cabo = BT funciona; com cabo = connect/page timeout, sem scan.
- Áudio por cabo (UAC1 + HID para botões) sempre foi estável — não mexer.
- BlueZ **não expõe** o serviço GATT vendor (0000a001 + 00001001/00001002) para este dispositivo. Qualquer tentativa de write GATT cai em ServiceUnknown.
- O canal real de controle é **SPP/RFCOMM** (UUID 00001101, canal 1).
- Framing usado pelo fone: `0xFF <len> <cmd> <count> <params...>` (exatamente como reverse do APK 4.0.7 + Quicky + Jieli RCSP concepts).

## Solução que funciona (2026-06-14)

1. Remova o cabo.
2. Conecte o QCY H3S via Bluetooth normalmente.
3. Use:
   - `bin/qcy-ctl` (shell wrapper mais simples)
   - `bun run src/cli/ble.ts ...` (agora delega para o mesmo caminho)
   - `bin/qcy-spp-raw` diretamente (baixo nível)

Binário C (`bin/qcy-spp-raw`) abre socket RFCOMM cru e envia os pacotes. Funcionou no primeiro teste ao vivo.

## Comandos principais

Ver `bin/qcy-ctl --help` ou o README.

## O que ainda falta (depende de você)

- Confirmação auditiva/funcional:
  - ANC on/off/transparency realmente alteram o cancelamento/passthrough?
  - Game mode muda latência ou qualidade percebida?
  - Volume obedece?
  - LDAC ON/OFF (com o risco de restart)?
- Depois disso podemos avançar para 0x17 (ANC avançado com níveis), 0x4A (GameConfig), EQ, Key remapping, etc.

## HFP / Microfone (separado)

Este problema (mic inaudível ou distorcido em CVSD) é independente do controle de features.
- BrowserOS / agentes pesados corrompem SCO.
- Configs antigas (wireplumber 50-bt-hfp-fix.conf com msbc=false, transcription-safe.sh, qcy-mic-recover.sh) ainda valem.
- Atualmente o source bluez_input costuma ficar SUSPENDED mesmo com headset-head-unit forçado.

Não misture as duas frentes a não ser que você peça explicitamente.

## Resumo

- Controle de features: **resolvido via SPP** (binários prontos e integrados).
- Validação de que os comandos fazem o que esperamos: **aguardando seu relatório**.
- Mic/HFP: thread separado, ainda em investigação.

Qualquer comando novo ou ajuste — só pedir.
