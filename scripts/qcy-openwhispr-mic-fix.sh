#!/usr/bin/env bash
# Ajusta OpenWhispr para não preferir mic da placa-mãe.
# Feche o OpenWhispr antes de rodar (ou reinicie depois).
set -euo pipefail

leveldb="${HOME}/.config/open-whispr/Local Storage/leveldb"

if pgrep -f '/opt/openwhispr/open-whispr' >/dev/null 2>&1; then
  printf '\033[1;33mOpenWhispr aberto — aplicando mesmo assim; reinicie o app depois.\033[0m\n' >&2
fi

python3 <<'PY'
import os, shutil, time

leveldb = os.path.expanduser("~/.config/open-whispr/Local Storage/leveldb")
changed = False

for fn in os.listdir(leveldb):
    if not fn.endswith((".log", ".ldb")):
        continue
    path = os.path.join(leveldb, fn)
    with open(path, "r+b") as f:
        data = bytearray(f.read())
    if b"preferBuiltInMic\x05\x01true" in data:
        data = data.replace(b"preferBuiltInMic\x05\x01true", b"preferBuiltInMic\x06\x01false")
        with open(path, "r+b") as f:
            f.write(data)
        changed = True

print("preferBuiltInMic=false" if changed else "preferBuiltInMic já estava false ou não encontrado")
PY

printf '\033[1;32mPronto. Abra o OpenWhispr → Configurações → Dictation → desligue "Preferir microfone interno" se ainda aparecer ligado.\033[0m\n'