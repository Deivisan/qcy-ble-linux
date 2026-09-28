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

## 15. mSBC no dongle Barrot 33fa:0012 — DESCARTADO (com medição, 25/09/2026)

⚠️ **Item 15 anterior dizia "mSBC impossível por falta de altsetting"** — isso
estava **errado/incompleto**. O que realmente acontece está em
[`docs/KERNEL-BTUSB-BARROT.md`](./docs/KERNEL-BTUSB-BARROT.md). Resumo do que
foi medido com o btusb patcheado (`0.8-barrot1`):

- A negociação mSBC no ar é **perfeita**: `eSCO`, RX/TX 60 bytes, `Air mode:
  Transparent`, USB isoc em **alt 3**, frames `dlen 72`, milhares de pacotes
  capturados no `btmon`.
- Mas o áudio é **100% mudo**, com ~**9 800 "corrupted SCO packet" em 25s**
  (~400/s). Transcrição do resultado: `e e e e e e e e` (lixo).
- Causa: o endpoint isocrono do Barrot no alt 3 entrega quadros de **25 bytes**
  (`wMaxPacketSize 0x0019`); um frame mSBC precisa de **72**. O
  `btusb_recv_isoc()` tenta remontar 3 quadros/frame SCO e dessincroniza →
  `validate_sco_handle()` rejeita → pacote descartado. Alt máximo real do
  dongle é o 5, com **49 bytes** — insuficiente para 72. **Limite de firmware.**

**Armadilha que make o mic falhar sozinho:** com `bluez5.enable-msbc = true`
o BlueZ escolhe por conta própria o perfil `headset-head-unit` (codec MSBC,
**prioridade 6**) em vez do `headset-head-unit-cvsd` (prioridade 5) — e o
usuário não pediu nada. Por isso `enable-msbc = false` é obrigatório.

### 15b. `force_scofix=1` era o culpado oculto do mSBC

`force_scofix=1` → `HCI_QUIRK_FIXUP_BUFFER_SIZE` → `hci_read_buffer_size()`
usa `sco_mtu=64` em vez dos **255 que o controlador reporta** (medido no
`btmon`: `SCO MTU: 255`). O guard `hdev->sco_mtu >= 72` do caminho alt-3/mSBC
ficava sempre falso. Desligar o `force_scofix` **libera** o alt 3 — e foi
assim que se descobriu que o alt 3 também não funciona neste hardware. Mantido
**ligado** por causa do filtro de pacote duplicado (transporte medido em
666 pacotes eSCO/s constantes, sem lacunas, com e sem).

**Lição:** `force_scofix` tem efeito colateral não óbvio; medir o
`sco_mtu` real do controlador (`btmon` → `Read Buffer Size`) antes de culpar
o hardware.

## 16. Chrome/Wispr Flow "não capta" com enumeração OK (22/09/2026)


`enumerateDevices()` via CDP lista **"QCY H3S"** em audioinput e `getUserMedia`
abre stream `live, unmuted` com autoswitch p/ HFP — enumeração NUNCA foi o
problema (Chrome usa Pulse/pipewire-pulse, não portal; `--ozone-platform` é
irrelevante p/ mic). Quando o transporte SCO está saudável, o caminho Chrome
entrega áudio VIVO (validado: CDP gUM + `parecord` simultâneo, absmax=570 em
sala silenciosa).
Se o stream abrir `live` mas capturar zeros, o culpado é o transporte SCO
wedged (ver itens 7/14/15), não o Chrome: recovery = `disconnect/connect` (ou
restart `bluetooth`), `./scripts/qcy-mic-default.sh`, e UM ciclo limpo
A2DP→HFP com voz real (testes `parecord` em rajada logo após toggle mSBC/WP
restart podem dar zeros transitórios — o link eSCO precisa de um ciclo limpo
para estabilizar; veredito final sempre com VOZ, nunca só silêncio).
Sites (ex. WhatsApp Web) podem estar presos no device "Padrão" antigo (bug
Chromium 40275281: `default` deviceId gruda): selecionar **QCY H3S**
explicitamente no dropdown do mic do site + reiniciar o Chrome após mudar o
default do sistema.
## 17. O DKMS btusb-barrot sumiu na troca de distro (25/09/2026)

**Este era o bug real, e ele estava por baixo de todos os outros.** O projeto inteiro foi
escrito em jun/2026 sobre `linux-cachyos 7.0.11-1-cachyos` com um módulo DKMS
`btusb-barrot` (patch de eSCO count + bypass de `validate_sco_handle`).
A máquina hoje é **Arch + `linux-zen 7.2.7-zen1-1`** (instalado 20/09,
DKMS recriado 23/09). O DKMS do btusb **não foi recriado**:

```
dkms status   -> so broadcom-wl
/usr/src/     -> sem btusb-barrot-*
modinfo -n btusb -> /lib/modules/.../kernel/drivers/bluetooth/btusb.ko.zst   (stock)
```

Ou seja: **todo o histórico de "mic consertado em junho" virou ficção** — o
sistema vinha rodando o btusb stock. Sintomas que isso explica, todos
documentados aqui como "misteriosos": alt 0 em HFP, 466 `corrupted SCO`/boot,
`SCO packet for unknown connection handle 384`, áudio "horrível".

**Lição:** antes de caçar bug de config, verificar `modinfo -n <modulo>` e
`cat /sys/module/<modulo>/version`. Toda afirmação "já funcionava" neste repo
depende do DKMS existir — e ele não sobreviveu à troca de kernel.

## 18. Erros do ambiente que o repo assume errado (25/09/2026)

| Repo assume | Realidade |
|---|---|
| `linux-cachyos 7.0.11-1-cachyos` | `linux-zen 7.2.7-zen1-1` (Arch) |
| CachyOS | Arch Linux puro |
| KDE Plasma | **COSMIC** (`XDG_CURRENT_DESKTOP=COSMIC`) |
| `btusb` com DKMS Barrot | stock do kernel, sem patch |
| advice "KDE → Mostrar dispositivos virtuais" | sem equivalente no COSMIC |

Erros do `cosmic-settings-daemon` / `cosmic-applet-audio` no journal: **nenhum
de áudio** — só renderização de textura (`Failed to render texture ... import for
wrong devices`) e tema (`error loading system dark theme`). O default source
ficou estável em `bluez_input` durante 25s de monitoramento. O COSMIC **não**
troca o microfone de device.

## 19. Falso positivo de verificação: `absmax` não prova microfone (25/09/2026)

O critério antigo (`absmax>=500 && rms>=30 → PASS`) deu **PASS** para
gravações que eram ruído de pacote corrompido. Pior: os scripts do repo
usavam `sample_spec` 48000 Hz e não checavam buracos.

Corrigido nesta sessão:
- `scripts/qcy-audio-analyze.py` — floor de ruído, % de frames com sinal, maior
  buraco interno, clipping. Só marca FALHA em casos duros; pausa natural de fala
  virou informação, não reprovação.
- `scripts/qcy-mic-transcribe.sh` + `scripts/qcy-transcribe.py` — **veredito
  real por transcrição** (faster-whisper, modelo `small`, `pt`).
- `scripts/qcy-mic-diagnose.sh` L6 — vereditos novos
  (`FAIL_SILENCIO` / `FAIL_ESCASO` / `FALHA_SO_RUIDO` / `QUEBRADO` /
  `CANDIDATO_OK`), e `PASS` deixou de existir.
- `qcy-mic-quality-test.sh` ainda usa `ok=1` por absmax — **não confiar** nele.

**Lição:** validação de áudio de Bluetooth tem de ser por texto, não por
número. Barulho tem absmax alto.

---

# 28/09/2026 — Sessão de correção do microfone (a que resolveu)

Contexto: "microfone funciona na primeira vez e depois morre". Esta seção
registra **todos os caminhos errados** tomados nesta sessão, para não repetir.

## 20. ERRO: "o dongle ignora 45% dos comandos SCO" (dado inventado por grep)

Afirmei que o firmware do Barrot recusava ~45% das aberturas de canal de voz.
Base: `grep -c 'Synchronous Connect Complete'` numa captura do btmon.

**O grep é que estava errado.** O btmon trunca linhas com a largura do terminal:

```
> HCI Event: Synchronous Connect Complete (0x2c) plen 17        #8     <- casa
> HCI Event: Synchronous Connect Compl.. (0x2c) plen 17  #4193         <- NAO casa
```

Recontagem correta: **9 de 9, todas `Status: Success`.** O "45%" era artefato.
Nada de errado no firmware.

## 21. ERRO: patch P1 (eSCO-aware SCO count) — premissa falsa, causava dano

O patch mais perigoso desta sessão inteira. Partiu da afirmação de que
`hci_conn_num(hdev, SCO_LINK)` devolveria `0` para conexões eSCO.

**Falso.** Em `include/net/bluetooth/hci_core.h`:
```c
case SCO_LINK:
case ESCO_LINK:            /* fallthrough */
        return h->sco_num; /* o MESMO contador */
```
Somar os dois = `2 * sco_num`. E `data->sco_num` é **índice da tabela
`alts[3] = {2,4,5}`** em `btusb_work()` → com 1 conexão, P1 escolhia altsetting
**4** em vez de **2**; com 2+, lia fora dos limites.

Funcionava **por acidente** (dobrava o número e caía na tabela, gaindo um alt
maior). Ao remover o P1 a captura foi a **zero bit-exato** — a prova.

**Lição:** patch de kernel se verifica lendo `/lib/modules/$(uname -r)/build/`,
nunca de memória.

## 22. ERRO: medir microfone sem ninguém falando

"3 de 5 capturas mudas" era o silêncio de um quarto vazio. `rms` baixo sem voz
não é falha — é o sinal correto de um microfone funcionando em silêncio.

**Lição:** só voz prova microfone. `scripts/qcy-mic-probe.sh` foi criado
por causa disso (descarta a janela de 3 s e julga por amplitude).

## 23. ERRO: daemon e timers próprios prendendo o perfil em HFP

`scripts/qcy-mic-warm.sh` + `qcy-mic-warm.service` + **dois timers**
(qcy-mic-warm.timer, qcy-mic-default.timer) que ressuscitavam um
`pw-record --target bluez_input... --raw /dev/null` infinitamente. Com captura
"ativa" o sistema — **corretamente** — nunca voltava para A2DP. Usuário
relatou "fica preso no perfil handsfree".

Além disso, `~/.local/state/wireplumber/bluetooth-autoswitch` tinha
`saved-headset-profile:...=headset-head-unit`, o que fazia o WirePlumber
restaurar HFP em cada reconexão.

**Resolvido:** processos mortos, timers `disable`d, estado salvo para
`a2dp-sink`. A troca de perfil agora é 100% nativa do WirePlumber
(`bluetooth.autoswitch-to-headset-profile = true`) e validada nos dois sentidos.

**Lição:** audite processos/timers próprios antes de culpar o stack de áudio.

## 24. NÃO ERA: bug upstream WirePlumber 0.5.17 × kernel 7.2

`wireplumber#1013` descreve exatamente "1 de 12 passa, só a primeira" em
WP 0.5.17 com kernel 7.2, com o mesmo log `Failure in Bluetooth audio transport`.
Workaround oficial: voltar para 0.5.15.

**Testado aqui e NÃO se manifesta:** 3/3 ciclos A2DP↔HFP com áudio real
capturado após a correção do altsetting. Não houve necessidade de downgradear
o WirePlumber. Registrado para não gastar tempo com isso se reaparecer —
e para saber que, se aparecer de novo, é aqui.

## 25. NÃO ERA: COSMIC

Suspeitei do `cosmic-applets-audio` (existem bugs reais dele: o slider mostra
100% quando o volume real é 0%, e o applet re-estabelece streams de BT —
`cosmic-settings#2018`, `cosmic-settings#536`).

**Descartado:** `pactl get-default-source` aponta corretamente para
`bluez_input.84:AC:60:05:55:2C`, e o teste acústico provou que o áudio chega
ponta a ponta. Se um dia o slider do COSMIC mentir sobre o volume, aí sim.

## 26. SOLUÇÃO: P3 — altsetting isocrônico do Barrot

O Barrot não anuncia 2EV3 → `btusb_work()` escolhia **altsetting 1 (9 bytes)**
para pacotes SCO CVSD de **60 bytes** → remontagem quebrada → `corrupted SCO`
e áudio mudo **com o HCI reportando o link como perfeito**.

Patch: flag `BTUSB_BROKEN_SCO_ALT` (BIT 30) que faz o Barrot usar a tabela
`alts[3]` do próprio upstream → **altsetting 2 (17 bytes)**.

Resultado: 3/3 ciclos com áudio capturado, `corrupted SCO` = 0. Detalhes e
receita em `docs/KERNEL-BTUSB-BARROT.md`.
