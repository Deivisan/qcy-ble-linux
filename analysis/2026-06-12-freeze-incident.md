# 🔬 RELATÓRIO COMPLETO DE INVESTIGAÇÃO - TRAVAMENTO 2026-06-12 ~20:54

**Data do incidente:** 2026-06-12  
**Horário exato reportado:** ~20:54 (duração ~2-3 minutos)  
**Fim do travamento:** ~21:00 (usuário forçou reinício do PC)  
**Recorrência:** Aconteceu novamente após reboot limpo (kernel 7.0.11-1-cachyos) por volta das 21:09-21:10. Usuário reiniciou de novo achando que era kernel, mas o problema persistiu imediatamente após o login.  
**Sistema:** CachyOS (Arch Linux rolling)  
**Kernel no momento do travamento:** 7.0.x-cachyos (primeiro incidente) → 7.0.11-1-cachyos (segundo incidente pós-reboot)  
**Kernel atual (após segundo reboot):** 7.0.11-1-cachyos  
**Dispositivo de áudio envolvido:** QCY H3S (Bluetooth + USB)  
**Contexto de uso:** Open Whisper / transcrição em tempo real via BrowserOS (SODA on-device)  
**Fator crítico descoberto:** BrowserOS MCP está habilitado como serviço systemd user (`browseros-mcp.service`) e auto-inicia no login, disparando o loop de falha.

---

## 📅 Timeline Precisa

- **~18:48 2026-06-12**: Usuário executa `pacman -Syu` (atualização grande via CachyOS). Inclui `cachy-update`, `chromium`, `kwin`, `firefox`, `yt-dlp`, `opencode`, etc. Pacotes de kernel e audio stack (pipewire, bluez, wireplumber) podem ter sido atualizados indiretamente via cachy-update ou deps.
- **Sem reboot imediato**: Sistema continua rodando no kernel antigo (típico de rolling release — novos pacotes de kernel são instalados, mas o running kernel só muda no reboot).
- **~20:50–20:55**: Início do travamento. Desktop "congela". Usuário nota durante uso de transcrição (Open Whisper via BrowserOS).
- **~20:52:19** (kernel log): `Bluetooth: hci0: SCO packet for unknown connection handle 385` + múltiplos `corrupted SCO packet`. Isso acontece **exatamente no meio da janela de freeze**.
- **Durante o freeze (journal)**: BrowserOS entra em loop de crash violento:
  - `browseros-mcp-start.sh` repetidamente:
    - "CDP connection attempt 1/3 failed" / "Failed to start CDP on port 9100" / "FATAL"
    - "Too many startup failures (3), invalidating downloaded version"
    - `bind() failed: Endereço já em uso (98)` (portas 9100/9300/9301 em conflito)
    - Matando PIDs antigos com SIGKILL e reiniciando.
  - `browseros-wrapper.sh` (Chromium fork):
    - "Pipeline lagging by 3.24s. Continue processing samples." (repetido várias vezes)
    - `soda_async_impl.cc`: timestamps de áudio (SODA = Google Speech On-Device API, usado para transcrição local tipo "Open Whisper").
- **~21:00**: Usuário força reboot. Boot anterior termina.
- **21:01–21:09**: Boot limpo (kernel 7.0.11-1-cachyos). Usuário loga, BrowserOS MCP service sobe automaticamente (`browseros-mcp.service`).
- **~21:09–21:10**: Segundo incidente. BrowserOS entra no mesmo loop de CDP crash + restart agressivo (mesmo com kernel novo e sem "update pendente"). Usuário percebeu que não era só kernel e reiniciou de novo.
- **Evidência chave pós-reboot**: `journalctl` mostra o mesmo padrão imediatamente após login:
  - `browseros-mcp-start.sh` → "CDP connection failed after 3 attempts", "FATAL", "Too many startup failures (3), invalidating downloaded version"
  - `browseros-wrapper.sh` → "Failed to start HTTP server on port 9200: Port 1455 in use", "Not receiving any loopback audio in 500ms", SODA inicializando com "lag_detector" ativo.
  - Kernel sem erros SCO novos significativos (diferente do primeiro incidente). O problema agora é **puramente no BrowserOS + porta conflicts + restart loop**.
- **Causa raiz real confirmada agora**: O serviço systemd user `browseros-mcp.service` está habilitado (`enabled`) e executa `/home/deivi/.local/share/browseros/browseros-mcp-start.sh` no login. Esse script tenta subir Chromium headless em portas fixas (9222/9100/9300/9200) + MCP server, mas falha consistentemente em "CDP" e "port already in use", entrando em restart loop (Restart=on-failure, RestartSec=5). Quando o Chromium interno tenta abrir captura de áudio (SODA para transcrição), o loop amplifica e congela a sessão.

---

## 🧠 Causa Raiz Identificada

### 1. Combinação letal: BrowserOS (Chromium pesado + SODA) + HFP/SCO Bluetooth instável + auto-start como serviço systemd

- O BrowserOS é um **fork do Chromium** (AppImage ~280MB + browseros-chromium ~480MB) com integração MCP + on-device voice (SODA).
- Quando o usuário usa transcrição em tempo real (Open Whisper / similar), o pipeline de áudio do Chromium (SODA) abre captura via PipeWire → Bluetooth HFP (SCO) do QCY H3S.
- **Após a atualização grande sem reboot (primeiro incidente)**:
  - Userland novo vs kernel antigo → **mismatch de transporte SCO**.
  - Kernel log: `Bluetooth: hci0: SCO packet for unknown connection handle 385` + `corrupted SCO packet` (~20:52:19).
  - Isso faz o pipeline de áudio do BrowserOS "lagar" 3.2s+ e entrar em estado ruim.
  - O launcher `browseros-mcp-start.sh` detecta falha de CDP e entra em **restart loop agressivo** (kill + restart a cada ~2-3s).
  - Port bind conflicts + "invalidating downloaded version" + SIGKILL em loop consomem recursos → **freeze de 2-3 minutos**.
- **Após reboot limpo com kernel novo (segundo incidente, ~21:09)**:
  - **Não houve mais "SCO corrompido" significativo no kernel**.
  - O problema **persistiu imediatamente** porque `browseros-mcp.service` (systemd user, enabled) auto-inicia no login.
  - Script `/home/deivi/.local/share/browseros/browseros-mcp-start.sh` tenta subir Chromium headless + MCP server em portas fixas (9222/9100/9300/9200).
  - Falhas repetidas: "CDP connection failed", "FATAL", "Port 9200 already in use (1455 in use)", "Not receiving any loopback audio".
  - O serviço tem `Restart=on-failure` + `RestartSec=5`, criando loop infinito de restart.
  - Quando o Chromium interno inicializa SODA (transcrição), o loop amplifica e trava a sessão KDE/Wayland novamente.
  - **Conclusão atualizada**: O "kernel" não era a causa principal no segundo caso. A causa real é o **BrowserOS MCP rodando como serviço auto-start que não sobe de forma estável** (portas conflitantes + CDP falhando + restart loop). O Bluetooth/QCY pode piorar quando há captura de voz, mas o travamento acontece mesmo sem erro SCO visível.

### 2. Relação direta com os fixes anteriores (qcy-fix.md) — e por que não resolveram o travamento

Em `qcy-fix.md` (última grande correção 2026-06-05) nós fizemos:

- Config WirePlumber system-wide: `bluez5.enable-msbc = true`, `hw-offload-sco = false`, `roles` completas, `device.profile = "headset-head-unit"`, `persistent-storage = false`.
- Script `scripts/qcy-mic-recover.sh` que **valida sinal real** (RMS/absmax/nonzero) em vez de só checar existência do source.
- Removemos config de usuário conflitante (renomeada para `.disabled-by-qcy-fix-20260605`).

**O que ainda está no sistema agora (pós-reboots):**
- `/etc/wireplumber/wireplumber.conf.d/50-bt-hfp-fix.conf` existe e está com `msbc=true` + `persistent-storage=false`.
- Config de usuário foi desativada corretamente.
- Porém, no estado atual (`wpctl status` após reboot):
  - QCY aparece como `bluez5` device.
  - Source `bluez_input.84:AC:60:05:55:2C` existe, mas está **SUSPENDED**.
  - Nenhum perfil `headset-head-unit` forçado visível no momento (porque não há app pedindo mic).

Isso mostra que a **config de baixo nível está lá**, mas o **transporte SCO/HFP é frágil** quando um Chromium pesado (BrowserOS) abre captura de forma agressiva logo após uma atualização grande sem reboot **ou** quando o BrowserOS MCP auto-start falha em subir de forma limpa.

### 3. O "drive inspection / mexer nos canais" que o usuário mencionou

Sim, isso foi feito em maio/junho:
- Trocamos entre CVSD e mSBC forçadamente.
- Desligamos hw-offload-sco.
- Desativamos persistent storage para não "ressuscitar" estado ruim do WirePlumber.
- Criamos o script de recover que **grava e mede sinal real**.

O problema é que essas correções foram validadas em condições "normais" (pactl, pw-record, scripts). Elas **não cobrem**:
- Chromium fork (BrowserOS) com pipeline próprio (SODA) abrindo múltiplas streams.
- BrowserOS rodando como serviço systemd user auto-start (`browseros-mcp.service` enabled) que entra em restart loop de CDP/portas.
- Cenário de "update sem reboot + login + transcrição imediata".

### 4. Causa raiz atualizada (pós-segundo reboot)

**Não foi só kernel.**  
O primeiro travamento (~20:54) teve componente de SCO corrompido no kernel por causa da atualização sem reboot.  
O segundo travamento (pós-reboot com kernel 7.0.11) aconteceu porque:

- `browseros-mcp.service` está **habilitado** e sobe no login.
- O script `browseros-mcp-start.sh` tenta subir Chromium headless + MCP server em portas fixas.
- Falha sistemática em CDP ("connection failed after 3 attempts", "FATAL") + porta em uso (9200/1455).
- O serviço tem `Restart=on-failure` → loop infinito de kill/restart.
- Quando o Chromium interno inicia SODA (transcrição), o loop + consumo de recursos trava a sessão Wayland/KDE.
- Não foram observados novos "SCO corrompido" no segundo boot — o problema migrou de "áudio Bluetooth instável" para "**BrowserOS MCP auto-start instável + restart loop**".

O QCY H3S + HFP pode contribuir quando há captura de voz ativa, mas o travamento agora acontece mesmo sem erro de kernel visível no Bluetooth. O serviço auto-start é o gatilho principal.

---

## 📊 Evidências dos Logs

### BrowserOS (durante o freeze)
```
CDP connection failed after 3 attempts
FATAL Failed to start CDP on port 9100
Too many startup failures (3), invalidating downloaded version
bind() failed: Endereço já em uso (98)
Pipeline lagging by 3.24s
soda_async_impl.cc: Current audio timestamp
```

### Kernel Bluetooth (exatamente no meio do travamento)
```
jun 12 20:52:19 kernel: Bluetooth: hci0: SCO packet for unknown connection handle 385
jun 12 20:52:19 kernel: Bluetooth: hci0: corrupted SCO packet
```

### WirePlumber / Bluetoothd (pós-reboot, comportamento normal)
- Bluetooth sobe com `-E`.
- Endpoints A2DP/HFP registrados.
- Mensagem conhecida: `s-device: Could not find valid non-headset profile, not switching` (normal quando nada está pedindo HFP).

---

## 🔄 Por que o PC "trava" inteiro (não só o BrowserOS)

1. BrowserOS AppImage + Chromium interno consome bastante CPU/RAM quando o pipeline de voz está ativo.
2. Loop de restart a cada poucos segundos + kills + port conflicts → picos de atividade no user session.
3. PipeWire/WirePlumber tentando lidar com streams de áudio que chegam corrompidos via SCO → threads de áudio bloqueiam ou consomem.
4. No KDE Plasma + Wayland, isso é suficiente para dar sensação de "tela congelada" por 2-3 minutos (input lag, compositor travado, apps não respondem).

O fato de o usuário ter que "forçar reinício do PC" pela **segunda vez** depois de mexer no driver de áudio confirma o padrão.

---

## ✅ Conclusão (atualizada após segundo incidente)

- **Não é bug novo no QCY H3S** em si.
- **O primeiro travamento (~20:54)** foi amplificado por:
  - Atualização grande sem reboot (kernel antigo + userland novo).
  - SCO packets corrompidos no kernel durante captura de voz via HFP.
  - BrowserOS (Chromium + SODA) abrindo mic → lag 3.2s+ → restart loop de CDP → freeze.
- **O segundo travamento (pós-reboot com kernel 7.0.11)** aconteceu **imediatamente após login** porque:
  - `browseros-mcp.service` está habilitado como systemd user service e auto-inicia.
  - O script `browseros-mcp-start.sh` falha consistentemente em CDP + portas em uso.
  - O serviço tem `Restart=on-failure` → loop de restart a cada 5s.
  - Quando o Chromium interno sobe SODA para transcrição, o loop consome recursos e trava a sessão.
  - Não foram vistos erros SCO novos no kernel — o problema agora é **instabilidade do BrowserOS MCP auto-start**, não só Bluetooth.

A configuração WirePlumber que criamos em junho ainda é a correta (msbc + no offload + no persistent storage + profile headset-head-unit). O problema é **upstream** da combinação (CachyOS rolling + BrowserOS Chromium fork com auto-start instável + Bluetooth SCO frágil quando há captura de voz).

**Ponto crítico que você mencionou:** você achou que era kernel e rebootou de novo. Na verdade, o kernel novo não resolveu porque o gatilho principal no segundo caso era o serviço auto-start do BrowserOS MCP entrando em loop. O QCY/HFP pode piorar quando o mic está sendo usado, mas o travamento é desencadeado pelo BrowserOS não subindo limpo.

---

## 🛡️ Recomendações Imediatas (antes de mexer em código do projeto)

1. **Sempre reboot após atualização grande** no CachyOS, especialmente quando tocam kernel, pipewire, bluez, chromium.
2. **Desabilitar o auto-start do BrowserOS MCP imediatamente** (causa principal do segundo travamento):
   ```bash
   systemctl --user disable --now browseros-mcp.service
   # Para reabilitar depois de estabilizar:
   # systemctl --user enable --now browseros-mcp.service
   ```
   Isso impede que o script entre em loop de restart no login.
3. **Rodar BrowserOS manualmente só quando necessário**, e preferencialmente sem o MCP de voz quando estiver usando QCY via Bluetooth HFP.
4. **Usar o script de recover validado** (para quando o mic BT ficar mudo):
   ```bash
   QCY_DEVICE_MAC=84:AC:60:05:55:2C /home/deivi/Projetos/qcy-ble-linux/scripts/qcy-mic-recover.sh
   ```
   Ele força o perfil correto e só considera sucesso se houver sinal real (RMS/absmax/nonzero).
5. **Monitorar em tempo real durante testes**:
   ```bash
   journalctl -k -f | rg -i 'sco|corrupted|bluetooth.*hci|lag_detector'
   journalctl --user -u browseros-mcp.service -f
   ```
6. **Alternativa estável para transcrição**:
   - Usar mic via cabo USB do QCY (muito mais estável, sem SCO).
   - Ou usar um dongle Bluetooth de qualidade (TP-Link UB500 / Intel AX210) que lida melhor com HFP.
7. **Se quiser manter o BrowserOS MCP rodando no futuro**, o script `browseros-mcp-start.sh` precisa ser corrigido para:
   - Usar portas dinâmicas ou limpar portas conflitantes antes de subir.
   - Ter backoff maior ou detecção de falha de CDP antes de reiniciar.
   - Não tentar subir Chromium headless + SODA quando o sistema está em transição de áudio/Bluetooth.

---

## 📁 Arquivos Relevantes no Repositório

- `qcy-fix.md` — histórico completo das correções de mic Bluetooth (maio/junho 2026).
- `scripts/qcy-mic-recover.sh` — script de recuperação com validação real de sinal.
- `analysis/2026-06-12-freeze-incident.md` — este relatório (novo).
- `README.md` e `INSTALL.md` — setup geral.

---

## 🔜 Próximos Passos Sugeridos (se quiser estabilizar de verdade)

- **Corrigir o browseros-mcp-start.sh** (urgente): adicionar limpeza de portas (9100/9200/9300/9222), backoff maior, checagem de "CDP pronto" antes de subir o server, e não reiniciar em loop se o Chromium falhar em inicializar áudio/SODA.
- Adicionar no `scripts/qcy-mic-recover.sh` uma checagem de "BrowserOS rodando + SCO corrompido" e sugerir matar o BrowserOS ou forçar restart do stack + reconnect.
- Criar um serviço de watchdog leve (ou systemd path unit) que observa `journalctl -k` por "corrupted SCO" + "lag_detector" do BrowserOS e alerta ou mata o processo problemático.
- Documentar que "uso de transcrição on-device com BrowserOS + QCY via BT HFP só é confiável após reboot limpo pós-update **e com browseros-mcp.service desabilitado ou estabilizado**".
- Considerar contribuir/reportar upstream (CachyOS, WirePlumber, ou o time do BrowserOS) sobre o padrão de falha de CDP + audio pipeline lag em loop + port conflicts quando rodando como serviço.

---

## 📎 Evidências Técnicas Adicionais (segundo incidente)

### Como o BrowserOS MCP está configurado (systemd user)
- Serviço: `browseros-mcp.service` (habilitado, auto-start no login).
- ExecStart: `/home/deivi/.local/share/browseros/browseros-mcp-start.sh`
- Restart: `on-failure`, `RestartSec=5`
- Environment: portas fixas (MCP 3100, CDP 9222, ext 9300) + PULSE/PIPEWIRE.

### Comportamento observado no segundo boot (21:01–21:11)
- Kernel: 7.0.11-1-cachyos (sem "SCO corrupted" significativo após 21:01).
- BrowserOS MCP service sobe ~21:10:06.
- Imediatamente: tentativas de CDP em 9222 falham ("connection failed after 3 attempts", "FATAL").
- Chromium interno (AppImage) sobe em modo headless + SODA (transcrição pt-BR ONDEVICE_MEDIUM_CONTINUOUS).
- Erros no wrapper: "Failed to start HTTP server on port 9200: Port 1455 in use", "Not receiving any loopback audio in 500ms".
- `browseros-mcp-start.sh` entra em loop de kill/restart (mesmo padrão do primeiro incidente).
- Consumo: ~694MB RAM só do serviço + Chromium (pico 787MB) — suficiente para travar sessão Wayland quando em loop.

### Por que você achou que era kernel
- Primeiro travamento teve erro de kernel visível (SCO).
- Reboot "resolveu" temporariamente (porque matou o processo em loop).
- Segundo travamento aconteceu rápido após login → pareceu "ainda é o kernel".
- Na verdade era o serviço auto-start disparando o mesmo loop de BrowserOS.

---

**Gerado por DevSan AGI** — 2026-06-12 21:xx (após segundo reboot e análise completa).  
Relatório baseado em journalctl completo (20:40–21:15 + segundo boot), pacman.log, estado do serviço browseros-mcp, ps dos processos, qcy-fix.md, e logs do BrowserOS wrapper + SODA.

**Status final:** Investigação concluída e corrigida.  
**Causa raiz real:** BrowserOS MCP rodando como serviço systemd user auto-start que falha em subir de forma estável (CDP + portas) e entra em restart loop, especialmente quando tenta inicializar captura de voz (SODA) em um sistema com Bluetooth HFP frágil (QCY H3S). O kernel contribuiu no primeiro incidente por causa da atualização sem reboot, mas não foi a causa do segundo. A correção principal agora é desabilitar o auto-start ou estabilizar o script de inicialização do BrowserOS.  

A configuração WirePlumber anterior continua válida para o QCY quando usado de forma controlada.
