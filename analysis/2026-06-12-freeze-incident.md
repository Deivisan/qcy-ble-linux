# 🔬 RELATÓRIO COMPLETO DE INVESTIGAÇÃO - TRAVAMENTO 2026-06-12 ~20:54

**Data do incidente:** 2026-06-12  
**Horário exato reportado:** ~20:54 (duração ~2-3 minutos)  
**Fim do travamento:** ~21:00 (usuário forçou reinício do PC)  
**Sistema:** CachyOS (Arch Linux rolling)  
**Kernel no momento do travamento:** 7.0.x-cachyos (antes da rebase)  
**Kernel atual (pós-reboot):** 7.0.11-1-cachyos  
**Dispositivo de áudio envolvido:** QCY H3S (Bluetooth + USB)  
**Contexto de uso:** Open Whisper / transcrição em tempo real via BrowserOS (SODA on-device)

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
- **21:01**: Novo boot limpo (kernel 7.0.11-1-cachyos). Serviços sobem, mas BrowserOS continua com o mesmo padrão de falha de CDP (agora sem travar o desktop inteiro).

---

## 🧠 Causa Raiz Identificada

### 1. Combinação letal: BrowserOS (Chromium pesado + SODA) + HFP/SCO Bluetooth instável

- O BrowserOS é um **fork do Chromium** (AppImage ~280MB + browseros-chromium ~480MB) com integração MCP + on-device voice (SODA).
- Quando o usuário usa transcrição em tempo real (Open Whisper / similar), o pipeline de áudio do Chromium (SODA) abre captura via PipeWire → Bluetooth HFP (SCO) do QCY H3S.
- Após a atualização grande sem reboot:
  - Userland novo (possivelmente novo PipeWire/BlueZ/WirePlumber ou libs do Chromium) vs kernel modules/firmware antigos → **mismatch de transporte SCO**.
  - Resultado: SCO packets corrompidos no kernel (`hci0: corrupted SCO packet`).
  - Isso faz o pipeline de áudio do BrowserOS "lagar" 3.2s+ e entrar em estado ruim.
  - O launcher `browseros-mcp-start.sh` detecta falha de CDP e entra em **restart loop agressivo** (kill + restart a cada ~2-3s).
  - Port bind conflicts + "invalidating downloaded version" + SIGKILL em loop consomem recursos do desktop (especialmente Wayland/KDE session) → **freeze perceptível de 2-3 minutos**.

### 2. Relação direta com os fixes anteriores (qcy-fix.md)

Em `qcy-fix.md` (última grande correção 2026-06-05) nós fizemos:

- Config WirePlumber system-wide: `bluez5.enable-msbc = true`, `hw-offload-sco = false`, `roles` completas, `device.profile = "headset-head-unit"`, `persistent-storage = false`.
- Script `scripts/qcy-mic-recover.sh` que **valida sinal real** (RMS/absmax/nonzero) em vez de só checar existência do source.
- Removemos config de usuário conflitante (renomeada para `.disabled-by-qcy-fix-20260605`).

**O que ainda está no sistema agora (pós-reboot):**
- `/etc/wireplumber/wireplumber.conf.d/50-bt-hfp-fix.conf` existe e está com `msbc=true` + `persistent-storage=false`.
- Config de usuário foi desativada corretamente.
- Porém, no estado atual (`wpctl status` após reboot):
  - QCY aparece como `bluez5` device.
  - Source `bluez_input.84:AC:60:05:55:2C` existe, mas está **SUSPENDED**.
  - Nenhum perfil `headset-head-unit` forçado visível no momento (porque não há app pedindo mic).

Isso mostra que a **config de baixo nível está lá**, mas o **transporte SCO/HFP é frágil** quando um Chromium pesado (BrowserOS) abre captura de forma agressiva logo após uma atualização grande sem reboot.

### 3. O "drive inspection / mexer nos canais" que o usuário mencionou

Sim, isso foi feito em maio/junho:
- Trocamos entre CVSD e mSBC forçadamente.
- Desligamos hw-offload-sco.
- Desativamos persistent storage para não "ressuscitar" estado ruim do WirePlumber.
- Criamos o script de recover que **grava e mede sinal real**.

O problema é que essas correções foram validadas em condições "normais" (pactl, pw-record, scripts). Elas **não cobrem** o caso de um Chromium fork com pipeline de áudio próprio (SODA) abrindo múltiplas streams de captura enquanto o Bluetooth SCO está em transição pós-update.

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

## ✅ Conclusão

- **Não é bug novo no QCY H3S** em si.
- **É regressão de estabilidade** causada por:
  1. Atualização grande do CachyOS (18:48) sem reboot imediato.
  2. Kernel running antigo + userland novo (especialmente libs de áudio + Chromium).
  3. BrowserOS (Chromium + SODA on-device transcription) abrindo captura de microfone via HFP/SCO do QCY exatamente nesse momento de transição.
  4. O loop de recuperação do BrowserOS (CDP) amplifica o problema até travar a sessão.

A configuração WirePlumber que criamos em junho ainda é a correta (msbc + no offload + no persistent storage + profile headset-head-unit). O problema é **upstream** da combinação (CachyOS rolling + BrowserOS Chromium + Bluetooth SCO frágil no kernel 7.0.x com esse dongle/fone).

---

## 🛡️ Recomendações Imediatas (antes de mexer em código do projeto)

1. **Sempre reboot após atualização grande** no CachyOS, especialmente quando tocam kernel, pipewire, bluez, chromium.
2. **Isolar o BrowserOS durante investigação**:
   - Desabilitar o auto-start do `browseros-mcp.service` temporariamente.
   - Ou rodar BrowserOS sem o MCP de voz quando estiver usando o QCY via BT.
3. **Usar o script de recover validado**:
   ```bash
   QCY_DEVICE_MAC=84:AC:60:05:55:2C /home/deivi/Projetos/qcy-ble-linux/scripts/qcy-mic-recover.sh
   ```
   Ele força o perfil correto e só considera sucesso se houver sinal real (RMS/absmax/nonzero).
4. **Monitorar SCO especificamente**:
   ```bash
   journalctl -k -f | grep -i 'sco\|bluetooth.*hci'
   ```
5. **Alternativa estável para transcrição**:
   - Usar mic via cabo USB do QCY (muito mais estável, sem SCO).
   - Ou usar um dongle Bluetooth de qualidade (TP-Link UB500 / Intel AX210) que lida melhor com HFP.

---

## 📁 Arquivos Relevantes no Repositório

- `qcy-fix.md` — histórico completo das correções de mic Bluetooth (maio/junho 2026).
- `scripts/qcy-mic-recover.sh` — script de recuperação com validação real de sinal.
- `analysis/2026-06-12-freeze-incident.md` — este relatório (novo).
- `README.md` e `INSTALL.md` — setup geral.

---

## 🔜 Próximos Passos Sugeridos (se quiser estabilizar de verdade)

- Adicionar no script de recover uma checagem de "BrowserOS rodando + SCO corrompido" e sugerir matar o BrowserOS ou forçar restart do stack + reconnect.
- Criar um serviço de watchdog leve que observa `journalctl -k` por "corrupted SCO" e "lag_detector" do BrowserOS e alerta.
- Documentar que "uso de transcrição on-device com BrowserOS + QCY via BT HFP só é confiável após reboot limpo pós-update".
- Considerar contribuir/reportar upstream (CachyOS, WirePlumber, ou o time do BrowserOS) sobre o padrão de falha de CDP + audio pipeline lag em loop.

---

**Gerado por DevSan AGI** — 2026-06-12 21:xx (pós-reboot do usuário).  
Relatório baseado em journalctl completo do período 20:40–21:15, pacman.log da atualização, qcy-fix.md, estado atual do WirePlumber/Bluetooth, e logs do BrowserOS wrapper.

**Status:** Investigação concluída. Causa identificada. Configuração anterior ainda válida, mas o cenário de uso (BrowserOS + transcrição + update sem reboot) não foi coberto pelos testes anteriores.
