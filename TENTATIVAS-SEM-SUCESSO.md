# QCY H3S — Tentativas que NÃO resolveram (ou pioraram)

**Data:** 15/06/2026  
**Objetivo deste arquivo:** Evitar repetir abordagens que já falharam. Leia antes de qualquer nova mudança.

**Hardware:** QCY H3S `84:AC:60:05:55:2C` + dongle UGREEN Barrot `33fa:0012` + CachyOS kernel `7.0.11-1-cachyos` + PipeWire 1.6.6 + WirePlumber 0.5.14 + KDE Plasma.

**Sintoma real do usuário (autoritativo):**
- Troca de perfil A2DP↔HFP **sempre funcionou** automaticamente — **não é o problema**.
- O problema era: **mic não gravado / não reconhecido pelos apps** (OpenWhisper, BrowserOS, YouTube voz, etc.).
- Às vezes o medidor de volume reage ao barulho, mas o sistema **não deixa selecionar** o microfone.

**✅ Solução que funcionou (15/06/2026):** `docs/MIC-SETUP-FINAL.md` + `./scripts/qcy-install-mic-setup.sh`

Resumo: autoswitch A2DP↔HFP + watcher + default `bluez_input` + OpenWhispr `preferBuiltInMic=false` + BrowserOS wrapper `--ozone-platform=x11`.

---

## 1. Culpar / forçar troca de perfil manualmente

| O que foi feito | Resultado |
|-----------------|-----------|
| Forçar HFP permanente via `54-qcy-mic-loopback-fix.lua` (`autoswitch=false`, `device.profile=headset-head-unit-cvsd`) | **Ignorado** pelo WirePlumber 0.5 (formato Lua antigo). Quando chegou a valer em sessões antigas, **quebrou música** e gerava erros no bluetoothd. |
| `qcy-mic-default.sh` (versão antiga) forçando HFP + timer a cada 45s | Erros `Connection reset by peer` no HFP gateway; briga com autoswitch natural. |
| `52-qcy-hfp-isolated-test.conf` (HFP fixo, autoswitch off) | Isolou teste mas **atrapalhou uso normal** — desativado. |
| Scripts dizendo "rode qcy-mic-default antes de usar mic" como se perfil fosse o bloqueio | **Diagnóstico errado.** Autoswitch funciona; `parecord` troca perfil sozinho. |

**Lição:** Não desabilitar `bluetooth.autoswitch-to-headset-profile`. Não forçar HFP permanente.

---

## 2. Patch DKMS agressivo (USB alt / eSCO hook)

| O que foi feito | Resultado |
|-----------------|-----------|
| Forçar `bAlternateSetting` no `HCI_EV_SYNC_CONN_COMPLETE` | **Regressão total:** mic parou de ser reconhecido pelo sistema. |
| Contagem eSCO alterada de forma agressiva (sem validação) | Instabilidade; usuário pediu **revert**. |
| `apply-btusb-barrot-sco-fix.sh` (patch amplo) | **Removido** após quebrar. |

**O que ficou e parece correto (kernel):**
- Bypass Barrot em `btusb_validate_sco_handle()` (handles 385, 4095, etc.)
- Patch `btusb_sco_conn_count()` = SCO_LINK + ESCO_LINK (`apply-btusb-esco-count-fix.sh`)
- Com HFP ativo: `usb_alt` vai para 2 (antes ficava 0)

**Lição:** Patch cirúrgico no kernel OK; patch que força USB alt no evento errado = quebra.

---

## 3. Configs Lua em `bluetooth.lua.d/` (WirePlumber 0.4)

| Arquivo | Status | Problema |
|---------|--------|----------|
| `51-qcy-auto-hfp.lua` | `.disabled-conflict` | WP 0.5 **não carrega** — só gera warning no journal. |
| `54-qcy-mic-loopback-fix.lua` | `.disabled-esco-fix-20260615` | Idem. Conteúdo útil mas **formato morto**. |
| `52-qcy-hfp-stable.lua`, `53-qcy-mic-buffer.lua` | `.disabled-revert` | Revertidos após instabilidade. |

**Lição:** Migrar para `~/.config/wireplumber/wireplumber.conf.d/*.conf` (SPA-JSON). Lua em `bluetooth.lua.d/` = ruído.

---

## 4. Confundir “teste passou” com “apps funcionam”

Várias vezes os testes mostraram sucesso, mas o usuário continuou sem mic nos apps:

| Teste | Passou? | Apps funcionaram? |
|-------|---------|-------------------|
| `pw-record --target bluez_input...` | Sim (absmax 20k+) | Não necessariamente |
| `parecord -d bluez_input...` | Sim (às vezes) | Não necessariamente |
| `qcy-hfp-isolation-test.sh` loopback + real-sco | Sim | Não |
| Medidor KDE reage ao barulho | Sim | Não = não é gravação real nos apps |

**Causa descoberta depois:**
- **Pulse (`pactl`) e PipeWire (`wpctl`) tinham defaults diferentes.**
  - `pactl get-default-source` → `bluez_input` (OK para alguns apps)
  - `wpctl` Settings → `alsa_input` placa-mãe (KDE portal, BrowserOS, OpenWhisper usam isto)
- Mic BT no WP 0.5 fica em **Filters** (`bluez_input`), não em **Sources** no A2DP.
  - KDE esconde sem **“Mostrar dispositivos virtuais”**.
- `object.register = false` no loopback — alguns caminhos de enumeração ignoram.

**Lição:** Validar **os três** juntos:
```bash
pactl get-default-source
wpctl status | tail -5    # Audio/Source deve ser bluez_input
parecord + app real (BrowserOS/OpenWhisper)
```

---

## 5. Script `qcy-mic-default.sh` (versão intermediária) — ativamente prejudicial

Versão que **setava placa-mãe como default no A2DP** “para apps não pegarem source fantasma”:

```bash
# REMOVIDO — ERRADO
pactl set-default-source alsa_input...   # quando em A2DP
```

**Efeito:** Exatamente o oposto do necessário. Apps viam só mic da placa-mãe. Usuário: “não reconhece o microfone”.

**Versão atual (15/06 noite):** seta `bluez_input` em **pactl + wpctl** quando fone conectado.

---

## 6. Estado persistente WirePlumber sobrescrevendo correções

Arquivo `~/.local/state/wireplumber/default-nodes` frequentemente tinha:
```
default.configured.audio.source=alsa_input.pci-0000_0a_00.6.analog-stereo   # ERRADO
default.configured.audio.source.0=bluez_input.84:AC:60:05:55:2C             # certo mas não ativo
```

Após restart do WirePlumber ou ação do KDE, o default **voltava para analógico** até o timer/script rodar de novo.

**Janela de falha:** ~30s entre execuções do timer; loopback pode não existir logo após restart (perfil HFP some temporariamente).

---

## 7. Race: loopback não criado após restart

Sequência que quebra:
1. `systemctl --user restart wireplumber`
2. Card bluez só mostra perfis A2DP (HFP some por alguns segundos)
3. `has_headset_profile=false` → **sem loopback** `bluez_input`
4. `qcy-mic-default.sh` sai silenciosamente (`exit 0` linha 53-55)
5. Apps abrem → sem mic BT visível

**Recuperação observada:** `bluetoothctl disconnect/connect` ou esperar + restart wireplumber.

---

## 8. `qcy-mic-recover.sh` — perigoso se executado

- Escreve `/etc/wireplumber/wireplumber.conf.d/50-bt-hfp-fix.conf` com **`device.profile = headset-head-unit"` fixo**.
- `bluetooth.use-persistent-storage = false` — apaga hábito do autoswitch.
- Conflita com `51-qcy-h3s-bt.conf` do usuário.
- **Não rodar** sem saber — pode desfazer autoswitch.

---

## 9. Documentação desatualizada / enganosa

| Arquivo | Problema |
|---------|----------|
| `ESTADO_ATUAL.md` | Diz "CONECTADO E FUNCIONANDO"; cita `54-qcy-mic-loopback-fix.lua` como ativa; diz "força HFP" no mic-default. **Tudo desatualizado.** |
| `QCY-H3S-BLUETOOTH-ISSUE-REPORT.md` | Útil para histórico kernel, mas mistura estado de 14/06 com 15/06. |
| `qcy-fix.md` | Correto sobre SPP/controle; diz mic "thread separado, ainda em investigação" — **ainda verdade.** |

---

## 10. O que NÃO é o problema (confirmado em logs)

- Pairing / conexão BT (quando conecta, A2DP funciona)
- Autoswitch de perfil (funciona quando app abre stream no loopback)
- Cabo USB do fone (desliga BT — documentado em `qcy-fix.md`)
- BrowserOS “sozinho” como causa raiz (pode piorar SCO, mas mic já falha sem ele)

---

## 11. Config ativa HOJE (15/06/2026 noite)

| Componente | Arquivo / estado |
|------------|------------------|
| WirePlumber 0.5 | `~/.config/wireplumber/wireplumber.conf.d/51-qcy-h3s-bt.conf` |
| DKMS btusb | `btusb_sco_conn_count` + bypass Barrot em `validate_sco_handle` |
| modprobe | `/etc/modprobe.d/btusb-barrot-qcy.conf` → `force_scofix=1` |
| Mic default | `scripts/qcy-mic-default.sh` + timer 30s |
| bluetoothd | `/etc/systemd/system/bluetooth.service.d/override.conf` → `-E --experimental` |
| Lua antigo | Tudo `.disabled*` — não carrega |

---

## 12. Checklist para próximo agente (não repetir erros)

1. Ler este arquivo primeiro.
2. Verificar **wpctl E pactl** — devem apontar para `bluez_input.84:AC:60:05:55:2C`.
3. Verificar loopback existe: `wpctl status` → Filters → `bluez_input`.
4. Verificar perfil HFP disponível: `pactl list cards` → `headset-head-unit`.
5. Testar com **app real**, não só `parecord`.
6. KDE: "Mostrar dispositivos virtuais" no ícone de volume.
7. Não forçar HFP permanente sem pedido explícito do usuário.
8. Não re-aplicar patch DKMS agressivo de USB alt.

---

## 13. Hipóteses ainda abertas (pós-auditoria 15/06)

1. **Desync pactl/wpctl** volta após ação do KDE Plasma (precisa script mais robusto ou esperar loopback).
2. **Loopback só em Filters** — apps que listam só `Sources` não veem QCY no A2DP.
3. **Timer 30s** — janela grande sem default correto.
4. **`qcy-mic-default.sh` sai silencioso** se loopback ainda não existe (sem retry/wait).
5. **Agentes BrowserOS/OpenWhisper** competindo por SCO enquanto timer corrige default.

---

## 14. A2DP em reprodução (ex.: música no Chrome) zera o SCO no HFP (21/09/2026)

`parecord` no `bluez_input` com música tocando: perfil troca p/ HSP, `usb_alt=1`,
`btmon` mostra 5000+ pacotes eSCO sem erro — mas captura = **zeros absolutos**.
Com a música **pausada**: mesma chamada captura voz forte (absmax 9000+).

Causa: o H3S não faz A2DP+HFP simultâneo; com o stream A2DP aberto o takeover
do HFP fica incompleto (transport `sep2/fd0` falha no journal) e o SCO sobe
"oco". Também explica "áudio bugando" no Chrome durante ditado.

Workflow: **pausar a música antes de ditar** (autoswitch volta ao A2DP ~12s
depois). Não é bug de driver/config — é contenção de perfil. Validado com
`btmon` + `parecord` em ambas as condições.