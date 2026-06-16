#!/usr/bin/env bash
# Corrige btusb: HFP moderno usa eSCO, mas o driver só contava SCO_LINK.
# Resultado: USB isoc ficava em alt 0 durante HFP → mic mudo/intermitente.
set -euo pipefail

SRC="/usr/src/btusb-barrot-1.0/btusb.c"
MARKER="btusb_sco_conn_count"

if [[ ! -f "$SRC" ]]; then
  echo "DKMS btusb-barrot não encontrado em $SRC" >&2
  exit 1
fi

if grep -q "$MARKER" "$SRC"; then
  echo "Patch eSCO já aplicado."
else
  cp -a "$SRC" "${SRC}.bak-pre-esco-count-$(date +%s)"
  python3 - "$SRC" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
helper = """
static inline unsigned int btusb_sco_conn_count(struct hci_dev *hdev)
{
\treturn hci_conn_num(hdev, SCO_LINK) + hci_conn_num(hdev, ESCO_LINK);
}
"""
anchor = "static bool btusb_validate_sco_handle(struct hci_dev *hdev,"
if anchor not in text:
    raise SystemExit("anchor validate_sco_handle não encontrado")
text = text.replace(anchor, helper + "\n" + anchor, 1)
text = text.replace(
    "hci_conn_num(hdev, SCO_LINK) < 1",
    "btusb_sco_conn_count(hdev) < 1",
)
old_notify = """\tif (hci_conn_num(hdev, SCO_LINK) != data->sco_num) {
\t\tdata->sco_num = hci_conn_num(hdev, SCO_LINK);
\t\tdata->air_mode = evt;
\t\tschedule_work(&data->work);
\t}"""
new_notify = """\tunsigned int sco_count = btusb_sco_conn_count(hdev);

\tif (sco_count != data->sco_num) {
\t\tdata->sco_num = sco_count;
\t\tdata->air_mode = evt;
\t\tschedule_work(&data->work);
\t}"""
if old_notify not in text:
    raise SystemExit("btusb_notify original não encontrado")
text = text.replace(old_notify, new_notify, 1)
open(path, "w").write(text)
print("Patch eSCO aplicado em", path)
PY
fi

echo "Recompilando DKMS btusb-barrot..."
sudo dkms build -m btusb-barrot -v 1.0 --force
sudo dkms install -m btusb-barrot -v 1.0 --force

echo "Recarregando módulo btusb..."
sudo modprobe -r btusb 2>/dev/null || true
sudo modprobe btusb force_scofix=1
sudo systemctl restart bluetooth
sleep 2

echo "OK. Teste: ./scripts/qcy-hfp-isolation-test.sh"