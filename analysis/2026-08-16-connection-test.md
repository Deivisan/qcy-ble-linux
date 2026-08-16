# Testes de Conexão — Sessão 2026-08-16

**Hardware:** QCY H3S `84:AC:60:05:55:2C` + dongle UGREEN Barrot `33fa:0012`
**SO:** CachyOS + BlueZ 5.87 (`bluetoothd -E --experimental`)
**Resultado geral:** ⚠️ conexão **não estabelecida** nesta sessão. Diagnóstico documentado abaixo.

---

## O que foi feito

1. **Verificação inicial** — fone pareado/bonded/trusted, mas `Connected: no`.
2. **`bluetoothctl connect`** → `br-connection-aborted-by-local` (device antigo no cache com estado inconsistente).
3. **Reset agressivo de emparelhamento** — removido o device do cache (`bluetoothctl remove`).
4. **Scan BR/EDR + LE** — **zero dispositivos** encontrados em múltiplas tentativas (5s–20s por scan), mesmo com `discoverable on` no controlador.
5. **Power cycle** do dongle via `bluetoothctl power off/on` — sem efeito no discovery.
6. **`qcy-spp-raw 0C 01`** → `Connection reset by peer`.
7. **RFCOMM socket python** (`AF_BLUETOOTH/BTPROTO_RFCOMM`, canal 1) → **conecta** mas timeout na primeira troca de dados.
8. **`btmgmt find`** → `Permission Denied` (esperado sem root).

---

## Diagnóstico

| Sintoma | Causa provável |
|---------|----------------|
| Scan não encontra NENHUM device (nem de vizinhos) | Dongle Barrot com discovery instável OU antena ambiente limpa |
| RFCOMM conecta (socket ok) mas reset/timeout | Fone conectado a outro device (celular) e recusando novo elo SPP |
| `br-connection-aborted-by-local` | Estado de pairing antigo corrompido (resolvido ao remover device) |

**Hipóteses abertas:**

1. O QCY H3S estava **conectado ao celular** durante a sessão → vira escravo e recusa novas conexões.
2. O dongle Barrot precisa de **scan mais longo** ou o discovery do BlueZ está filtrado.
3. O fone precisa estar em **modo pairing físico** (segurar L+R ~5–10s, LED piscando rápido) para aparecer no scan após remoção do cache.

---

## Checklist para próxima sessão (não repetir erros)

1. ✅ **Garantir que o fone NÃO está conectado a outro device** (celular/laptop) — desligar BT do celular antes.
2. ✅ **Colocar o fone em modo pairing físico** (L+R por 5–10s até LED piscar rápido) — necessário após `bluetoothctl remove`.
3. ✅ **Verificar LED do fone**: piscando rápido alternado = modo pairing; parado = já conectado a alguém.
4. ✅ **Scan com paciência**: `bluetoothctl scan on` por 30–60s, monitorando `NEW Device`.
5. ⚠️ Não usar `bluetoothctl remove` sem antes desconectar e verificar LED.
6. ⚠️ O RFCOMM conecta mas timeout — não perder tempo com socket manual; usar `bin/qcy-spp-raw`.
7. 🔧 Se scan continuar vazio: testar com outro dongle USB BT (hardware alternativo).

---

## Artefatos

- APKs analisados (682/689/715): descompilados em `/tmp/opencode/qcy-apk-682/` (não versionados)
- Documento de protocolo completo: `analysis/QCY-H3S-PROTOCOL-COMPLETO.md`
- Comandos prontos para validar quando o fone conectar:
  ```bash
  ./bin/qcy-ctl battery
  ./bin/qcy-ctl anc on
  ./bin/qcy-ctl anc trans
  ./bin/qcy-ctl volume 70
  ./bin/qcy-ctl game on
  ./bin/qcy-ctl music next
  ```