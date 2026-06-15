# QCY H3S + UGREEN BT6.0 (Barrot BR8554) - Relatório Completo do Problema

**Data:** 14 de Junho de 2026  
**Repositório:** `qcy-ble-linux`  
**Hardware:** AMD Ryzen 7 5700G + UGREEN Bluetooth 5.4 Dongle (USB ID: `33fa:0012` - Barrot BR8554 chipset) + Fone QCY H3S (MAC: `84:AC:60:05:55:2C`)

---

## Resumo Atual (Estado Real)

O fone conecta corretamente em **A2DP** (som de boa qualidade).  
O profile `headset-head-unit` (mSBC) consegue ser ativado, e o node `bluez_input.84:AC:60:05:55:2C` aparece no PipeWire.

**Porém o microfone não funciona de verdade.**  
O source fica em `SUSPENDED` e não captura áudio utilizável.

**Erro principal e recorrente no kernel:**

```log
Bluetooth: hci0: SCO packet for unknown connection handle XXXX
```

Os handles variam constantemente (2934, 375, 3547, 3510, 3037, 0, etc). Isso indica que o dongle Barrot está enviando pacotes SCO em handles que o driver `btusb` não reconhece, mesmo com nosso patch.

---

## Histórico de Descobertas (em ordem)

### Problemas Identificados

1. **Init Byte Corruption (FIXED)**
   - Dongle Barrot envia 1 byte extra no evento HCI.
   - Causava "Unexpected continuation: 1 bytes".
   - **Solução:** `btusb_barrot_urb_quirk()` + correção de ordem no `btusb_recv_intr()`.
   - Status: **OK** (zero ocorrências após rebuild).

2. **Conflito ofono + hsphfpd (FIXED)**
   - Ambos interferiam com o backend nativo do WirePlumber.
   - `ofono` e `hsphfpd` foram desabilitados, disabled e masked.

3. **Configuração bluetoothd fragmentada (FIXED)**
   - `main.conf` e `bluetooth.conf` conflitando.
   - Unificado em `/etc/bluetooth/main.conf` com `MultiProfile = multiple`.

4. **SCO Handle Validation (AINDA QUEBRADO - Problema Atual)**
   - QCY H3S / Barrot enviam SCO em handles não registrados.
   - Patch em `btusb_validate_sco_handle()` não está cobrindo todos os casos.
   - Resultado: Pacotes SCO são descartados → source fica suspended.

---

## O que Já Foi Feito

- DKMS module custom (`btusb-barrot`) versão 0.8 compilado e carregado.
- Patch inclui:
  - `btusb_barrot_urb_quirk()`
  - `btusb_is_barrot_dongle()`
  - Bypass parcial em `btusb_validate_sco_handle()`
- Configurações limpas de WirePlumber e bluetoothd.
- Múltiplos fresh pairing realizados.
- Testes de gravação com `pw-cat` e `arecord`.

---

## Arquivos Relevantes

- `QCY-H3S-BLUETOOTH-ISSUE-REPORT.md` ← este arquivo
- `/usr/src/btusb-barrot-1.0/btusb.c` → versão patchada
- `/etc/bluetooth/main.conf`
- `/etc/wireplumber/wireplumber.conf.d/50-bt-hfp-fix.conf`
- `ESTADO_ATUAL.md`
- `KERNEL-BARROT-PATCH-PLAN.md`

---

## Recomendações para Próximos Agentes

**Foco principal atual:**
Melhorar o bypass de SCO handles no driver `btusb`.

**Ideias para investigar:**
1. Tornar o bypass mais agressivo: aceitar **todos** os handles SCO quando o dongle for Barrot (`vendor=0x33fa`).
2. Implementar `btusb_add_sco_handle()` dinamicamente quando pacotes SCO chegarem.
3. Capturar btmon completo durante uma sessão HFP para ver exatamente qual handle o fone está usando.
4. Testar com `btusb` do kernel mainline mais recente (pode ter melhorias em SCO).
5. Analisar se o problema é no firmware do dongle Barrot (muitos relatos semelhantes).

**Regra importante:**
Nunca matar BrowserOS automaticamente quando o usuário reclamar de microfone picotando (conforme AGENTS.md).

---

**Última atualização:** 14/06/2026 - Após 3ª tentativa de patch SCO + análise profunda de logs.

Este relatório deve ser lido por qualquer agente que for continuar o trabalho.
