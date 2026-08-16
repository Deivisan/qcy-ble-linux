# AGENTS.md — QCY H3S Linux Protocol Project

## Visão Geral
Projeto de engenharia reversa para controle QCY H3S no Linux via SPP/RFCOMM + GATT. O foco principal é o repositório `qcy-ble-linux` que fornece `bin/qcy-ctl` + `scripts/` + CLI Bun para controle de ANC, Volume, Música, Game Mode, LDAC.

## Stack Atual
- **CLI:** Binário C (`bin/qcy-spp-raw`) + wrapper bash (`bin/qcy-ctl`)
- **TypeScript/Bun:** `src/cli/ble.ts` delegando para `bin/qcy-ctl`
- **Hardware:** QCY H3S (`84:AC:60:05:55:2C`) + dongle UGREEN Barrot
- **SO:** Arch Linux (CachyOS) + KDE Plasma + PipeWire 1.6.8 + WirePlumber 1.6.8
- **Runtimes:** Bun 1.3.14, Node 25.9.0, Python 3.14.6, Rust 1.96.1

## Histórico de Commits (últimos 15)
```
79090d3 feat(mic): config completa QCY H3S — OpenWhispr, BrowserOS, mSBC, autoswitch
302aeb9 docs: rewrite QCY H3S report with honest current status
0fbc537 docs: create comprehensive QCY H3S Bluetooth issue report for agents
910a663 feat: integrate proven SPP/RFCOMM control channel (bin/qcy-spp-raw + bin/qcy-ctl wrapper)
8dbd5f6 feat(BLE): implementação completa do protocolo QCY via BlueZ D-Bus
564d572 docs: correção do relatório de travamento - segundo incidente pós-reboot
4ed13a2 docs: relatório completo de investigação do travamento 2026-06-12 ~20:54
9e6db4a docs: add QCY H3S black product image and fix gitignore to allow docs/images
65d5bbd feat: initial release — CLI BLE + protocol docs
8dbd5f6 feat(BLE): implementação completa do protocolo QCY via BlueZ D-Bus
58b8542 feat(RE): análise estática do APK QCY 4.0.7-689 e captura BLE
51bc742 feat(Core): estrutura inicial bun+typescript implementada
```

## Documentação Capturada (via APK Reverse Engineering)

| Arquivo | Conteúdo | Status |
|---------|----------|--------|
| `analysis/QCY-H3S-PROTOCOL-COMPLETO.md` | Tabela completa de Cmd IDs (72 IDs), UUIDs GATT (25), modos ANC (2 rotas), formatação de pacote, diferenças entre builds 682/689/715. **Gerado via análise de smali**. | ✅ Concluído |
| `docs/MIC-SETUP-FINAL.md` | Configuração WirePlumber + OpenWhispr + BrowserOS para mic. | ✅ Concluído |
| `TENTATIVAS-SEM-SUCESSO.md` | Histórico de falhas e lições aprendidas (anti-repetição). | ✅ Concluído |
| `ESTADO_ATUAL.md` | Status ao vivo (15/06/2026): A2DP OK, mic via mSBC/HFP, controle SPP OK. | ⚠️ Atualização pendente (último commit 2 meses) |
| `docs/MIC-QUALITY.md` | Qualidade de áudio/mic. | ✅ Concluído |
| `QCY-H3S-BLUETOOTH-ISSUE-REPORT.md` | Histórico. | ⚠️ Desatualizado |

## Protocolos Capturados (engineering reverse)

### Transportes (2 rotas)
1. **SPP/RFCOMM** — UUID `00001101` — já funciona via `bin/qcy-spp-raw`
2. **GATT Write** — Service `0000A001`, Char `0000ae00` — identificado via APK reverse, **não validado no hardware ainda**

### Cmd IDs principais (validados)
| Cmd | Formato | Comando |
|-----|---------|---------|
| `0x04` | `[0x04 0x01 act]` | `music play/pause/next/prev` |
| `0x08` | `[0x08 0x03 L R 0x00]` | `volume L R` |
| `0x09` | `[0x09 0x01\|0x02]` | `game on/off` |
| `0x17` | `[0x17 0x03 mode subSence noiseValue]` | ANC avançado (GATT fallback) |
| `0x0C` | `[0x0C 0x01\|0x00\|0x03\|0x04]` | `anc on/off/out/trans` |
| `0x23` | `[0x23 0x01\|0x00]` | `ldac on/off` |
| `0x20` | `[0x20 ...]` | EQ multi-banda (pendente) |
| `0xFE` | `[0xFE 0x01 cmdID]` | REQUESTDATA — leitura de status |

### UUIDs GATT identificados
- Service: `0000A001-0000-1000-8000-00805f9b34fb`
- Write Char: `0000ae00-0000-1000-8000-00805F9B34FB`
- CCCD/Notify: `00002902-0000-1000-8000-00805f9b34fb`
- Jieli RCSP (v689+): `e49a25e0` / `e49a28e1`
- Custom various: 5f78df94, 9d84b9a3, 6c53db25, etc.

## Pending / To-Do

### Alta prioridade
1. **Validar comandos GATT** — testar escrita nos UUIDs `0000ae00`/`0000A001` via `gatttool` ou `bletool` quando SPP não disponível
2. **Implementar controle EQ** — CMDIDs 0x20/0x22/0x46/0x47 (presets + custom 10 bandas)
3. **ANC avançado 0x17** — validar `mode + subSence + noiseValue` no hardware real
4. **Leitura de respostas** — implementar canal RX no SPP (atualmente só TX)
5. **TUI/GUI** — criar interface front-end para o CLI Bun existente

### Média prioridade
6. **KEYFUN (0x2B)** — mapear funções dos botões físicos do fone
7. **Bateria pela GATT** — usar char `00002a06` em vez de `bluetoothctl`
8. **CMDIDs pendentes** — `0x06`, `0x0A`, `0x11`, `0x1E`, `0x1F`, `0x32`, `0x3A`, `0x3B`, `0x3D`, `0x3E`, `0x3F`, `0x43`, `0x45`, `0xFE` (não mapeados completamente)

### Baixa prioridade
9. **Perfil EasyEffects** — criar perfil DSP usando `~/.config/easyeffects/` sem mexer no firmware
10. **SPACE_AUDIO / ENV_ADAPTATION / INEAR_SENSITIVITY** — comandos ainda não mapeados completamente
11. **TWS_ENABLE / LED_SWITCH / LED_EFFECT** — testar configs extras
12. **Diferenças entre builds 682/689/715** — validar quais mudanças de protocolo são relevantes para o Linux

## Ferramentas e Habilidades Disponíveis
- `bin/qcy-spp-raw` — C sender via RFCOMM (compilado, testado)
- `bin/qcy-ctl` — wrapper bash delegando para spp-raw
- `src/cli/ble.ts` — CLI Bun TypeScript, delegando automaticamente para `qcy-ctl`
- `scripts/qcy-install-mic-setup.sh` — setup WirePlumber/OpenWhispr/BrowserOS
- `scripts/qcy-mic-diagnose.sh` — diagnóstico de mic
- `context7` — para documentação de bibliotecas externas
- `firecrawl` — para busca/web scraping quando necessário
- `tavily` — busca web para validações externas

## Regras de Contribuição / Development
- **CLI first, Bun first** — todo novo código deve ser CLI-first; prefira Bun/TypeScript quando possível
- **Minúsculas** — arquivos e comandos em Linux são case-sensitive
- **Autonomia total** — o agente DevSan opera sem pedir permissão
- **tmux é rei** — use tmux para sessões (mt, dev, sys)
- **Commit messages** — seguir padrão do repo: `feat/fix/docs/refactor/test/chore: descrição curta`
- **Branch** — main é a branch ativa; features new podem ser feitas em branches temporárias
- **Push** — confirmar que `git status` está limpo (ou apenas `easyeffects_source` untracked) antes de push
- **Teste** — `bun test` executa testes; mas sem testes automatizados para hardware BLE, validação é manual

## Próximos Passos (Roadmap)
1. Commit da documentação QCY-H3S-PROTOCOL-COMPLETO.md
2. Atualizar ESTADO_ATUAL.md com status atual (08/2026)
3. Validar 2-3 comandos GATT via `bluetoothctl` + `gatttool` fallback
4. Adicionar suporte EQ ao `qcy-ctl` ou wrapper Bun
5. Criar TUI minimalista (ncurses/bun) para controle rápido
6. Documentar diferenças protocolo build 682→689→715
7. Post-mortem: o que funcionou, o que não, próximos 3 meses