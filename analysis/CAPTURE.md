# Análise de Comandos BLE (Captura Dinâmica)

Esta pasta conterá os logs capturados com Frida.

## Como usar

1. **Instalar Frida no host**
   ```bash
   pip install frida-tools
   ```

2. **Instalar Frida server no Android**
   - Baixar a versão compatível da sua arquitetura (arm64, arm, x86) de https://github.com/frida/frida/releases
   - Executar no device:
     ```bash
     adb push frida-server /data/local/tmp/
     adb shell "chmod 755 /data/local/tmp/frida-server && /data/local/tmp/frida-server &"
     ```

3. **Executar o hook**
   ```bash
   frida -U -f com.qcymall.googleearphonesetup -l scripts/frida/qcy-ble-sniffer.js --no-pause
   ```

4. **Ações no app**
   - Abrir o app QCY
   - Conectar ao fone
   - Executar ações (ANC on/off, mudar EQ, etc.)
   - Cada escrita BLE aparecerá no console com hex dump.

5. **Salvar logs**
   Redirecionar saída para arquivo:
   ```bash
   frida ... 2>&1 | tee ble-capture-$(date +%s).txt
   ```

6. **Enviar logs para análise**
   Commit nesta pasta ou enviar para o DevSan.

---
**Nota:** O hook também captura exceções de stack para rastrear origem.