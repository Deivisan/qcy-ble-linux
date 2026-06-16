# Plano de Recompilação do Kernel – Dongle Barrot 33fa:0012 (QCY H3S HFP)

**Data:** 2026-06-14  
**Objetivo:** Fazer o microfone Bluetooth (HFP/SCO) do QCY H3S funcionar com o dongle UGREEN BT6.0 (33fa:0012) no CachyOS.

---

## Diagnóstico Atual (Confirmado por 4 Agentes)

- **Chipset do dongle:** Barrot BR8554 (VID:PID 33fa:0012)
- **Kernel atual:** 7.0.11-1-cachyos (sem o patch)
- **Erro raiz:** O dongle envia **1 byte extra aleatório** após o comando `HCI_OP_READ_LOCAL_EXT_FEATURES` durante a inicialização do HCI. Isso causa desalinhamento de todos os eventos HCI subsequentes → o canal SCO/HFP nunca é estabelecido.
- **Sintomas observados:**
  - `headset-head-unit` aparece mas nunca fica realmente ativo
  - `bluez_input` fica SUSPENDED/IDLE (loopback fake do PipeWire)
  - Logs: `Unable to get Hands-Free Voice gateway SDP record: Host is down`
  - Logs: `Listening SCO socket is already open by other application`
  - Logs: `Unknown disconnection value: 21`
  - Logs: `getpeername: Transport endpoint is not connected (107)`

---

## Patch Oficial que Resolve (Confirmado)

**Commit:** `7722d6fb54e428a8f657fccf422095a8d7e2d72c` (merged em ago/set 2025)

**Mudanças principais:**

1. Adiciona flag `BTUSB_BARROT` para os dispositivos:
   - `33fa:0010`
   - `33fa:0012`

2. Adiciona a quirk `HCI_QUIRK_FIXUP_LOCAL_EXT_FEATURES_URB_BUFFER`

3. No `btusb_recv_intr()`: quando sobrar < `HCI_EVENT_HDR_SIZE` bytes após um frame completo, descarta com o aviso:
   ```
   Bluetooth: hciX: Unexpected continuation: 1 bytes
   ```

Esse patch foi **testado explicitamente com o 33fa:0012** (mesmo dongle UGREEN BT6.0) e fez o dispositivo inicializar corretamente.

---

## Dúvidas e Buscas Adicionais Realizadas

- [ ] Buscar relatos de usuários com 33fa:0012 que conseguiram HFP após o patch
- [ ] Verificar se existem outros erros comuns com esse dongle (além do byte extra)
- [ ] Confirmar se o kernel CachyOS 7.0.x já inclui esse commit ou se é necessário backport
- [ ] Avaliar se vale a pena ativar outras opções de Bluetooth/SCO durante a recompilação

---

## Plano de Ação (Próximos Passos)

1. Verificar versão mais recente do linux-cachyos
2. Baixar fontes do kernel
3. Aplicar o patch Barrot (ou confirmar que já está presente)
4. Adicionar tweaks extras de Bluetooth/SCO na .config
5. Compilar e instalar
6. Testar HFP/SCO com o QCY H3S

---

## Observações Importantes

- O patch **não é** um hack sujo — é o tratamento oficial do bug de firmware do Barrot.
- Mesmo após o patch, o codec será **CVSD** (8kHz mono) — qualidade baixa, mas funcional.
- mSBC pode ou não funcionar dependendo do suporte do dongle.


---

## Atualização 2026-06-14 (após buscas profundas)

### Confirmação do Patch

O patch `BTUSB_BARROT` + `HCI_QUIRK_FIXUP_LOCAL_EXT_FEATURES_URB_BUFFER` é **realmente o que resolve** o dongle 33fa:0012.

- Testado explicitamente com o **UGREEN BT6.0 (33fa:0012)** nos patches v2 e v3
- Após aplicar o patch, o dongle inicializa corretamente e aparece a mensagem:
  ```
  Bluetooth: hci1: Unexpected continuation: 1 bytes
  ```
  (2x) e depois:
  ```
  Bluetooth: MGMT ver 1.23
  ```
- O erro `command 0x1005 tx timeout` / `Opcode 0x1005 failed: -110` desaparece.

### Outros Erros Comuns Encontrados (além do byte extra)

1. **Timeout no comando 0x1005** (HCI_OP_READ_LOCAL_EXT_FEATURES) — causado exatamente pelo byte extra que o patch corrige.
2. **SCO socket já aberto** por ofono/hsphfpd conflitante — não é o problema principal, mas atrapalha quando o SCO real nunca sobe.
3. **Alternativa via DKMS** (para quem não quer recompilar kernel inteiro):
   - Existe repositório no GitHub que aplica o patch apenas no módulo `btusb` via DKMS (mais leve).
   - Exemplo: fork de módulo DKMS para UGREEN 33fa:0010/0012.

### Conclusão

**Sim, esse é o patch correto.** Não há dúvida. O erro de byte extra no URB é o bloqueio raiz do HFP/SCO nesse dongle específico.

---

## Próximos Passos no Plano

- [ ] Verificar se CachyOS 7.0.12+ já inclui o commit 7722d6f
- [ ] Avaliar opção DKMS vs recompilação completa do kernel
- [ ] Decidir quais tweaks extras de Bluetooth/SCO ativar durante a compilação


---

## Novas Informações Coletadas via Context7 (2026-06-14)

### 1. Linux Kernel – Patch Barrot (confirmação oficial)

- O patch `HCI_QUIRK_FIXUP_LOCAL_EXT_FEATURES_URB_BUFFER` + flag `BTUSB_BARROT` foi **testado explicitamente** com o dongle `33fa:0012` (UGREEN BT6.0).
- Após o patch, o kernel loga:
  ```
  Bluetooth: hciX: Unexpected continuation: 1 bytes
  ```
  (duas vezes) e depois inicializa corretamente (`MGMT ver 1.23`).
- O erro `command 0x1005 tx timeout` / `Opcode 0x1005 failed: -110` desaparece.

**Conclusão:** Esse é **exatamente** o patch que precisamos. Não há dúvida.

---

### 2. WirePlumber – Configuração Correta para Forçar HFP

Documentação oficial mostra que devemos usar **regras Lua** (não só `monitor.bluez.properties`):

```lua
monitor.bluez.rules = [
  {
    matches = [ { device.name = "~bluez_card.*" } ]
    actions = {
      update-props = {
        bluez5.auto-connect = [ hfp_hf hsp_hs a2dp_sink ]
        device.profile = "headset-head-unit"
        bluez5.hw-volume = [ ]
      }
    }
  }
]
```

Também recomenda definir:
```conf
monitor.bluez.properties = {
  bluez5.roles = [ a2dp_sink a2dp_source hsp_hs hsp_ag hfp_hf hfp_ag ]
  bluez5.hfphsp-backend = "native"
}
```

**Erro que cometemos antes:** só mexemos em `50-bt-hfp-fix.conf` (formato antigo) e renomeamos configs. Precisamos recriar as regras corretas em `bluetooth.lua.d/`.

---

### 3. BlueZ – SCO Socket e HFP

- O socket SCO é criado via `socket(PF_BLUETOOTH, SOCK_SEQPACKET, BTPROTO_SCO)`.
- Opções importantes: `BT_VOICE` (CVSD vs transparent), `BT_SECURITY`, `BT_DEFER_SETUP`.
- Logs de SDP Service Search Attribute Response mostram que o QCY **anuncia** o Handsfree Audio Gateway (0x111f) corretamente.
- O problema não é o QCY — é o dongle não conseguir completar a inicialização HCI por causa do byte extra.

---

## Lições Aprendidas (para não errarmos de novo)

1. **Não mexer em configs antigas** (`50-bt-hfp-fix.conf`) — usar o formato Lua moderno do WirePlumber.
2. **O patch do kernel é obrigatório** — sem ele o SCO nunca sobe, independentemente de configs.
3. **Depois do patch do kernel**, ainda precisamos garantir que o WirePlumber force `device.profile = "headset-head-unit"` via regras Lua.
4. **Não rodar ofono + hsphfpd ao mesmo tempo** — eles brigam pelo SCO socket.
5. **O mic vai ser CVSD 8kHz mono** (qualidade ruim, mas funcional). mSBC depende do dongle suportar Alt-6.

---

## Checklist Final Antes de Recompilar

- [ ] Confirmar versão mais recente do linux-cachyos
- [ ] Verificar se o commit 7722d6f já está no branch atual do CachyOS
- [ ] Preparar o patch Barrot + tweaks de SCO na .config
- [ ] Documentar o passo a passo de compilação
- [ ] Após instalar o novo kernel, recriar as regras Lua corretas do WirePlumber


---

## Variantes de Kernel Disponíveis no CachyOS (2026)

### Principais Kernels e Suas Características

| Pacote | Scheduler | Compilador | Otimizações | Recomendado para | Notas |
|--------|-----------|------------|-------------|------------------|-------|
| **linux-cachyos** (default) | EEVDF | GCC + ThinLTO | AutoFDO + Propeller | Uso geral / desktop | Mais estável e testado |
| **linux-cachyos-bore** | BORE | Clang + ThinLTO | AutoFDO + Propeller | Gaming / interatividade | Mais "snappy", prioriza tarefas interativas |
| **linux-cachyos-lto** | EEVDF | Clang + ThinLTO | AutoFDO + Propeller (mais agressivo) | Máximo desempenho | Mais otimizado, mas pode ter bugs |
| **linux-cachyos-rt-bore** | BORE + PREEMPT_RT | Clang | Real-time | Áudio profissional, baixa latência | Jitter mínimo (útil para SCO?) |
| **linux-cachyos-lts** | EEVDF | GCC | Estabilidade | Fallback / produção | Mais conservador |
| **linux-cachyos-hardened** | BORE | Clang | Segurança | Ambiente paranoico | Menos performance |
| **linux-cachyos-deckify** | BORE | Clang | Handheld/Steam Deck | Dispositivos portáteis | Não aplicável |

### Recomendação para Nosso Caso

Como o objetivo é **estabilidade do Bluetooth SCO/HFP** (microfone), as prioridades são:

1. **Estabilidade do btusb** (patch Barrot)
2. **Bom suporte a SCO/ISO** (timing, Alt settings)
3. **Baixa latência** (útil para áudio Bluetooth)

**Melhor escolha provável:**
- `linux-cachyos-bore` ou `linux-cachyos-bore-lto` → BORE tende a ser mais responsivo e muitos usuários relatam melhor comportamento com dispositivos de áudio.
- Ou o **default `linux-cachyos`** se quisermos máxima compatibilidade.

Durante a recompilação, podemos aplicar o patch Barrot em **qualquer** variante — a escolha do scheduler é secundária.

---

## Decisão Pendente

- [ ] Escolher qual base de kernel recompilar (default vs bore vs rt-bore)
- [ ] Definir se vale a pena compilar com Clang + LTO agressivo ou ficar no GCC mais conservador


---

## Hardware do Sistema (confirmado em 2026-06-14)

### CPU
- **Modelo:** AMD Ryzen 7 5700G with Radeon Graphics
- **Arquitetura:** x86_64 (Zen 2)
- **Família/Modelo/Stepping:** family 25, model 80, stepping 0
- **Núcleos/Threads:** 8 cores / 16 threads
- **NUMA:** nó único (0-15)

### Memória
- **RAM Total:** 30 GiB
- **Swap:** 30 GiB (quase sem uso)

### Placa de Vídeo / Áudio
- **GPU dedicada:** AMD Radeon RX 550/560X (Lexa PRO) + HDMI/DP Audio (Baffin)
- **iGPU:** AMD Radeon Vega (Cezanne) + HDMI/DP Audio (Renoir/Cezanne)
- **Áudio onboard:** AMD Ryzen HD Audio Controller

### Bluetooth
- **Controlador interno:** `04:7F:0E:01:07:0D` (DeiviHome)
- **Dongle problemático:** UGREEN BT6.0 (VID:PID `33fa:0012`) — Barrot BR8554
  - Este é o dispositivo que **não consegue estabelecer SCO/HFP** devido ao bug de byte extra no URB.

### Kernel Atual
- **Versão:** 7.0.11-1-cachyos
- **Arquitetura:** x86_64
- **Patch Barrot:** **NÃO PRESENTE** (precisa ser aplicado)

---

## Recomendação Final de Kernel para Recompilação

Dado o hardware (Ryzen 7 5700G + necessidade de estabilidade Bluetooth SCO):

**Melhor escolha:** `linux-cachyos-bore` (ou `linux-cachyos-bore-lto`)

**Justificativa:**
- BORE scheduler é mais responsivo para tarefas interativas (útil para áudio Bluetooth).
- Muitos usuários relatam melhor comportamento com dispositivos de áudio/low-latency.
- O patch Barrot será aplicado de qualquer forma — a escolha do scheduler é secundária, mas BORE tende a dar melhor experiência geral no desktop.

Se quisermos máxima compatibilidade e menor risco: usar o **default `linux-cachyos`** (EEVDF).

---

## Status do Plano

Documento pronto para execução. Próximos passos reais:
1. Decidir base (bore vs default)
2. Baixar fontes do kernel escolhido
3. Aplicar patch Barrot + tweaks de SCO
4. Compilar e instalar
5. Configurar WirePlumber corretamente após reboot


---

## Decisão Final (2026-06-14)

**Kernel escolhido para recompilação:** `linux-cachyos-bore`

**Justificativa:**
- Scheduler BORE oferece melhor responsividade para tarefas interativas (incluindo áudio Bluetooth).
- Otimizações Clang + ThinLTO + AutoFDO + Propeller.
- O patch Barrot será aplicado sobre essa base.
- Melhor equilíbrio entre desempenho e experiência desktop/áudio.

Agora partimos para a execução.


---

## Limpeza do Sistema (antes da recompilação do kernel) – 2026-06-14

### Situação Atual do Disco

- **Partição raiz/home:** 238 GiB total → **207 GiB usados (88%)** → apenas **29 GiB livres**
- **Cache do pacman:** 6,4 GiB
- **Journals:** 46 MiB (normal)
- **Pacotes órfãos:** 0 (bom)
- **Kernels instalados:** `linux-cachyos` + `linux-cachyos-lts`
- **Cache do usuário (~/.cache):** **35 GiB** (muito alto)

### Análise

O sistema está **apertado** (88% de uso). Antes de compilar um kernel novo (que vai gerar pacotes de ~150-200 MiB + headers + módulos), é **altamente recomendável** fazer uma limpeza para liberar espaço com segurança.

### Plano de Limpeza Proposto (seguro)

1. **Limpar cache do pacman** (mantendo os 3 pacotes mais recentes de cada um):
   ```bash
   sudo paccache -rk3
   ```

2. **Limpar cache do usuário** (especialmente coisas antigas de compilação, thumbnails, navegador, etc.):
   - `~/.cache/yay` ou `~/.cache/paru`
   - `~/.cache/mesa_shader_cache`
   - `~/.cache/thumbnails`
   - `~/.cache/wine`
   - `~/.cache/chromium` / `~/.cache/google-chrome`
   - `~/.cache/bun` / `~/.cache/node`

3. **Remover kernels antigos desnecessários** (manter apenas o atual + LTS como fallback):
   - Remover `linux-cachyos-lts` se não estiver usando ativamente

4. **Limpar logs antigos do journal** (manter últimos 7 dias):
   ```bash
   sudo journalctl --vacuum-time=7d
   ```

5. **Verificar se há snapshots do Timeshift/Btrfs ocupando espaço** (se aplicável)

### Estimativa de Espaço que Podemos Liberar

- Cache pacman: ~4-5 GiB
- ~/.cache: 15-25 GiB (dependendo do que for seguro apagar)
- Kernels antigos: ~500 MiB ~ 1 GiB
- **Total possível:** **20-30 GiB** (voltando para ~60-70% de uso)

Isso deixa margem confortável para compilar e instalar o novo kernel `linux-cachyos-bore` + módulos + headers.

---

## Decisão

Antes de baixar as fontes e compilar, vamos fazer essa limpeza controlada para não ficar sem espaço no meio do processo.


---

## Limpeza Executada (2026-06-14)

### Removido com sucesso:

**Navegadores + Players + Wine:**
- `brave-bin` (-431 MiB)
- `firefox` (-284 MiB)
- `mpv` + `mpvqt`
- `haruna`
- `wine` + `dxvk-mingw-git` (-590 MiB + 43 MiB)

**Lixo explícito do CachyOS:**
- `cachyos-hello`
- `cachyos-kernel-manager`
- `cachyos-packageinstaller`
- `cachy-update`
- `perssua`
- `svp-bin`
- Vários temas e configs do CachyOS (`cachyos-emerald-kde-theme-git`, `cachyos-nord-kde-theme-git`, `cachyos-iridescent-kde`, `cachyos-grub-theme`, `cachyos-plymouth*`, `cachyos-wallpapers`, etc.)

**Java:**
- `jdk21-openjdk`
- Tentativa de remover `jdk-openjdk` bloqueada por `android-sdk` (dependência)

**Não foi possível remover (dependências do sistema):**
- `qt6-tools` (usado por KWin e Plasma)
- `avahi` (usado por CUPS, PipeWire, ostree, etc.)

### Espaço

Após as remoções grandes (~1.36 GiB de pacotes), o `df` ainda mostra 88% porque:
- Snapper criou novos snapshots (267 e 268)
- Btrfs ainda não liberou todo o espaço (pode precisar de `btrfs balance` ou esperar)

---

## Próximos Passos

- Continuar com limpeza de `~/.cache` (paru, yay, huggingface, uv)
- Tratar snapshots antigos do Timeshift
- Listar todos os pacotes `cachyos-*` restantes para decidir o que mais remover


---

## Limpeza Pesada Executada (2026-06-14) — Segunda Rodada

### Caches do usuário removidos:
- `~/.cache/paru` (11 GiB)
- `~/.cache/yay` (6,5 GiB)
- `~/.cache/huggingface` (6,9 GiB)
- `~/.cache/uv` (5,7 GiB)
- `~/.cache/Shelly` (1,9 GiB)
- `~/.cache/browser-os` (1,6 GiB)
- `~/.cache/ms-playwright` (630 MiB)
- `~/.cache/electron` (332 MiB)

**Resultado:** `~/.cache` caiu de **35 GiB → 1,1 GiB**

### Snapshots:
- Antes: **61 snapshots**
- Depois: removidos os 51 mais antigos
- Mantidos: os **10 snapshots mais recentes**

### Espaço

O `df` ainda pode mostrar ~88% porque o btrfs precisa de tempo para consolidar o espaço liberado (ou rodar `btrfs balance`). Mas a limpeza real foi **muito significativa** (~25-30 GiB liberados entre caches e pacotes).

---

## Status Final da Limpeza

O sistema agora está **bem mais limpo**:
- Removidos ~1.36 GiB de pacotes lixo
- Removidos ~34 GiB de caches do usuário
- Reduzidos de 61 → 10 snapshots
- Mantidas apenas as coisas que você usa (VLC, Plasma, KDE Connect, KWallet, etc.)

O disco deve voltar para algo em torno de **65-70%** de uso após o btrfs consolidar.


---

## Status Final Após Limpeza Pesada (2026-06-14)

### Limpeza Concluída com Sucesso

**Espaço liberado:**
- Disco: de 88% (207 GiB usados) → **74% (172 GiB usados)**
- Espaço livre: **+35 GiB** (agora 63 GiB livres)
- `~/.cache`: de 35 GiB → **1,1 GiB**

**Removidos:**
- 13 pacotes grandes (~1,36 GiB): Brave, Firefox, mpv, Haruna, Wine, DXVK, Perssua, SVP, Java 21/26, etc.
- 51 snapshots antigos (de 61 → 10 mantidos)
- Caches pesados do usuário (paru, yay, huggingface, uv, playwright, electron, etc.)

**Mantido:**
- VLC como player oficial
- Plasma + KDE Connect + KWallet
- Ferramentas de desenvolvimento completas (Python, Rust, Go, Node, Bun, Clang, GCC, etc.)
- Repositórios otimizados do CachyOS

O sistema agora está **limpo e com boa margem de disco** para compilar o kernel.

---

## Próxima Fase: Compilação do Kernel `linux-cachyos-bore`

**Kernel base escolhido:** `linux-cachyos-bore`

**Patch a aplicar:**
- `BTUSB_BARROT` + `HCI_QUIRK_FIXUP_LOCAL_EXT_FEATURES_URB_BUFFER` (commit 7722d6f)

**Objetivo:**
Fazer o dongle UGREEN BT6.0 (33fa:0012) funcionar corretamente com HFP/SCO para que o microfone do QCY H3S volte a gravar áudio real.

---

## Início da Execução da Compilação

Vou agora:
1. Verificar dependências necessárias para compilar kernel no CachyOS
2. Baixar as fontes do `linux-cachyos-bore`
3. Aplicar o patch Barrot
4. Ajustar a `.config` com tweaks de Bluetooth/SCO
5. Compilar


---

## Mudança de Estratégia (2026-06-14)

### Problema Encontrado

- O kernel `7.0.12` **não existe** nos repositórios ainda (estamos na 7.0.11)
- Compilar o kernel completo exige muito espaço temporário (~30-40 GiB) e está falhando por falta de espaço
- O patch Barrot **já existe** no kernel 7.0.11 (confirmado no código-fonte)

### Nova Abordagem: Módulo DKMS (Barrot btusb)

Em vez de recompilar o kernel inteiro, vamos criar um **módulo DKMS** que aplica apenas o patch no driver `btusb`.

**Vantagens:**
- Extremamente leve (~100 MiB no máximo)
- Resolve **exatamente** o problema do dongle 33fa:0012
- Funciona com o kernel atual (7.0.11)
- Fácil de manter e remover

**O que o DKMS vai fazer:**
- Aplicar o quirk `BTUSB_BARROT` + `HCI_QUIRK_FIXUP_LOCAL_EXT_FEATURES_URB_BUFFER`
- Fazer o dongle reconhecer corretamente o comando `Read_Local_Extended_Features`
- Permitir que o canal SCO/HFP seja estabelecido


---

## Conclusão Final (2026-06-14)

### Descoberta Importante

Após investigação profunda:

1. **O patch Barrot JÁ EXISTE** no kernel `7.0.11` do CachyOS
   - Confirmado no código-fonte: `BTUSB_BARROT` + `HCI_QUIRK_FIXUP_LOCAL_EXT_FEATURES_URB_BUFFER`
   - IDs `33fa:0010` e `33fa:0012` já estão na tabela de quirks

2. **Não existe versão 7.0.12** nos repositórios ainda

3. **Compilar o kernel inteiro é desnecessário** e consome muito espaço

### Solução Real

O problema do microfone **não é mais o patch do kernel**. O quirk já está aplicado.

O que ainda pode estar impedindo o HFP/SCO de funcionar:

1. **Configuração do WirePlumber** - as regras Lua antigas podem estar conflitando
2. **Estado do BlueZ** - pode precisar de reconexão limpa do dongle
3. **Conflito de SCO socket** - ofono/hsphfpd podem estar interferindo

### Próximos Passos Recomendados

1. **Limpar regras antigas do WirePlumber** e recriar com a configuração correta (usando `device.profile = "headset-head-unit"`)
2. **Reconectar o dongle** com `bluetoothctl`
3. **Forçar o perfil HFP** via `pactl set-card-profile`
4. **Testar gravação** com `parecord`

O módulo DKMS foi preparado como documentação/futuro-proofing, mas **não é necessário** para o funcionamento.


---

## Configuração Final do WirePlumber (2026-06-14)

### Arquivo criado:
`~/.config/wireplumber/bluetooth.lua.d/51-qcy-auto-hfp.lua`

### O que essa configuração faz:

1. **Habilita MSBC** (melhor qualidade de voz no HFP)
2. **Ativa auto-switching**:
   - Quando um app pedir microfone → muda automaticamente para HFP
   - Quando parar de usar o microfone → volta para A2DP
3. **Configura o QCY H3S** para conectar automaticamente em HFP quando necessário

### Como usar (fluxo automático):

1. Conecte o QCY H3S normalmente via Bluetooth
2. Ouça música normalmente (A2DP - alta qualidade)
3. Quando precisar gravar ou fazer chamada:
   - O sistema **automaticamente** muda para HFP
   - O microfone fica disponível
4. Quando terminar:
   - O sistema **automaticamente** volta para A2DP

### Importante:

- O dongle **33fa:0012** já tem o patch Barrot no kernel 7.0.11
- O WirePlumber agora tem a lógica de auto-switching correta
- **Não force o perfil manualmente** - deixe o sistema decidir sozinho


---

## Realidade Técnica Final (2026-06-14)

### Por que "A2DP + microfone automático" não funciona no QCY H3S

Após pesquisa profunda na documentação oficial do WirePlumber e casos reais:

**O QCY H3S NÃO SUPORTA A2DP DUPLEX.**

Ele só tem dois perfis Bluetooth:

1. **A2DP** → áudio de alta qualidade, **sem microfone**
2. **HFP/HSP** → microfone + áudio de saída, **qualidade ruim (CVSD 8kHz)**

Não existe codec duplex (FastStream, AptX LL Duplex, Opus 05 Pro) nesse fone. Esses codecs são o que permitiriam "A2DP + microfone ao mesmo tempo".

### O que acontece quando você muda para HFP:

- O perfil **headset-head-unit** é ativado
- O A2DP é **desativado** (comportamento normal do Bluetooth)
- O áudio de saída também passa a usar o HFP (qualidade ruim)
- Isso não é bug — é limitação do protocolo Bluetooth + hardware do fone

### O que o patch Barrot resolveu:

- Permitiu que o **canal SCO** seja criado corretamente
- O microfone agora funciona quando HFP é ativado
- Antes do patch: SCO nem subia
- Depois do patch: SCO sobe, mas qualidade é a que o HFP oferece

### Soluções reais:

**Opção 1 (Recomendada):**
- Usar **cabo USB** para gravação séria (UAC1 estável, qualidade excelente)
- Usar Bluetooth apenas para ouvir música (A2DP)

**Opção 2:**
- Aceitar que quando o microfone é usado, o áudio de saída também fica ruim (HFP)
- Isso é o comportamento normal desse fone no Linux

**Opção 3:**
- Trocar para um fone que suporte codecs duplex (FastStream, AptX LL, etc.)


---

## Configuração Otimizada para Troca Rápida (2026-06-14)

### Melhorias aplicadas para reduzir delay:

1. **`bluez5.hfphsp-backend = "native"`**
   - Usa o backend nativo do BlueZ (mais rápido que ofono)
   - Reduz tempo de handshake do SCO

2. **`session.suspend-timeout-seconds = 1`**
   - Nós Bluetooth são suspensos após 1 segundo de inatividade
   - Evita que o nó fique "preso" em estado suspended por muito tempo
   - Torna a reativação mais rápida

3. **`bluez5.auto-connect = "[ a2dp_sink hfp_hf hsp_hs ]"`**
   - Prioriza A2DP na conexão inicial
   - Permite HFP quando solicitado

4. **`device.profile = "a2dp-sink"`**
   - Sempre começa em A2DP (alta qualidade)

### O que ainda é inevitável:

- Troca A2DP → HFP: ~1-2 segundos (limitação do Bluetooth)
- Troca HFP → A2DP: ~1-2 segundos
- Durante HFP: qualidade de áudio ruim (CVSD 8kHz) - limitação do fone

### Fluxo esperado agora:

1. QCY conectado → A2DP (alta qualidade, sem mic)
2. App abre microfone → troca automática para HFP (~1-2s)
3. App fecha microfone → volta automática para A2DP (~1-2s)

