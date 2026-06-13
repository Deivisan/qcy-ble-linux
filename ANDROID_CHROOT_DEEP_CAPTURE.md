# QCY H3S — Deep Capture & Protocol Training from Android Chroot Linux

**Objetivo:** Usar o Linux poderoso dentro do chroot no seu dispositivo Android (com acesso root/total) para capturar o handshake real do app QCY, analisar os logs Bluetooth, extrair a sequência de init que falta e treinar o cliente Linux para finalmente controlar o fone.

Você está lendo isso de dentro do chroot Linux no Android. Este arquivo é o ponto de continuação oficial.

## 1. Estado Atual do Conhecimento (2026-06-12)

- Conexão RFCOMM (canal 1) funciona com privilégios elevados.
- Formato do protocolo está correto: `0xFF + length + cmd + params`.
- Comandos mapeados corretamente:
  - 0x0C = ANC (modo simples)
  - 0x09 = Game/Low Latency
  - 0x08 = Volume
  - 0x23 = LDAC
  - 0x17 = ANC avançado
- Problema real: O fone conecta mas **ignora** os comandos 0xFF porque falta a sequência de inicialização/handshake que o app oficial faz logo após conectar.
- Essa sequência provavelmente inclui:
  - Leitura de `SysExpandFunc` (capabilities do dispositivo)
  - Leitura do `VoiceMode` atual
  - Possível "enable" ou preparação do RCSP/JL stack
- Capturas feitas até agora foram majoritariamente "nós enviando comandos". Não capturamos de forma limpa o init completo gerado pelo app Android.

**Missão do chroot:** Capturar o tráfego real enquanto o app oficial está rodando, usando o poder do Linux completo + root no dispositivo.

## 2. Ferramentas que você tem no chroot (use todas)

- btmon (captura HCI completa)
- tshark / wireshark CLI
- Python 3 + pyserial, scapy (se instalado), raw sockets
- Bun / Node (se disponível)
- Acesso total a `/data`, `/data/vendor`, `/data/misc/bluetooth`
- `su` / root via KernelSU
- logcat via root
- bluez tools (se instalados no chroot)
- Acesso ao btsnoop_hci.log em tempo real ou pós-facto

## 3. Comandos de Descoberta e Captura (rode na ordem)

### 3.1 Descubra onde o btsnoop realmente está

```bash
# Descoberta agressiva
su -c 'find /data -name "*btsnoop*" 2>/dev/null'
su -c 'find /data -name "*hci.log" 2>/dev/null'
su -c 'find /data -name "*bluetooth*" -type d 2>/dev/null | head -20'
```

Caminhos mais prováveis:
- `/data/misc/bluetooth/logs/btsnoop_hci.log`
- `/data/vendor/bluetooth/logs/btsnoop_hci.log`

### 3.2 Capture o handshake de verdade (melhor método)

Enquanto o app QCY está rodando e você usa ANC, volume, LDAC, Game, etc.:

```bash
# Opção A — btmon direto no chroot (recomendado)
sudo btmon -w /tmp/qcy-chroot-handshake-$(date +%Y%m%d_%H%M%S).pcap

# Opção B — copiar o btsnoop enquanto o app está ativo (faça isso várias vezes durante o uso)
su -c 'cat /data/misc/bluetooth/logs/btsnoop_hci.log' > /tmp/qcy-btsnoop-from-android.log
su -c 'cat /data/vendor/bluetooth/logs/btsnoop_hci.log' > /tmp/qcy-btsnoop-vendor.log
```

### 3.3 Capture logcat completo com root (muito rico)

```bash
su -c 'logcat -d -b all' > /tmp/qcy-full-logcat.log

# Filtrado no QCY + Jieli/RCSP
su -c 'logcat -d -b all' | grep -iE 'qcy|jl_bt|rcsp|anc|voice|jldevice|sendDataToJlDevice|0x0C|0x09|0x17|0x23' > /tmp/qcy-app-logcat.txt
```

### 3.4 Análise imediata (scripts prontos no repositório)

Depois de capturar, rode:

```bash
# Python (mais completo)
python3 scripts/capture_multipoint.py analyze /tmp/seu-pcap.pcap

# Ou a versão Bun
bun run scripts/capture_multipoint.ts analyze /tmp/seu-pcap.pcap

# Script raiz de análise com root logs
/tmp/analyze-qcy-logs-root.sh   # se você copiou os logs para /tmp
```

## 4. O que procurar na análise (prioridades)

1. **Primeiros pacotes após conexão** (handshake/init) — especialmente leituras antes de qualquer 0xFF.
2. Comandos de leitura de capabilities (`SysExpandFunc`, `VoiceMode`, feature bits).
3. Qualquer "enable", "init", "auth" ou preparação do RCSP/JL stack.
4. Os comandos 0xFF reais que o app manda (compare com os nossos).
5. Respostas do fone (notificações) que indicam que ele "acordou".

## 5. Próximo passo depois da análise

- Extrair a sequência mínima de init.
- Implementar no cliente Linux (primeiro no Python raw ou no Bun/TS SPP).
- Testar enviando o init completo + depois os comandos normais (0x0C, 0x09, etc.).
- Se funcionar, portar para o cliente principal.

## 6. Dicas de poder no chroot

- Rode btmon e o app ao mesmo tempo (multipoint + app gerando tráfego).
- Use `su -c` agressivamente para acessar tudo.
- Se o chroot tiver bluez completo, experimente `bluetoothctl`, `sdptool`, `rfcomm` nativos.
- Capture em momentos estratégicos: logo após o app conectar, logo antes/depois de mudar ANC, etc.
- Guarde vários pcaps com nomes claros (ex: `qcy-anc-cycle.pcap`, `qcy-first-connect.pcap`).

## 7. Arquivos úteis já no repositório

- `scripts/capture_multipoint.py`
- `scripts/capture_multipoint.ts`
- `scripts/qcy-spp-raw.py` (cliente Python raw RFCOMM)
- `scripts/qcy-sudo.sh` (wrapper)
- `src/lib/ble-qcy-spp.ts` (cliente Bun)
- `ANDROID_CHROOT_DEEP_CAPTURE.md` (este arquivo)
- `ESTADO_ATUAL.md`

## 8. Quando voltar pro Linux do PC

Atualize o repo com os achados do chroot, implemente o init descoberto, e teste do PC normal (ou mantenha o trabalho dentro do chroot se for mais conveniente).

---

**Você está dentro do chroot Linux no Android agora.**

Siga a seção 3, capture enquanto usa o app, rode as análises, e me avise (ou continue sozinho) quando tiver os primeiros resultados.

Boa caçada. O poder está nas suas mãos aqui dentro.
