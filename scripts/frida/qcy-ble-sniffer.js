#!/usr/bin/env frida

/**
 * Frida Hook: QCY BLE Protocol Sniffer
 * Captura comandos writeCharacteristic e intercepta chamadas do SDK QCY
 *
 * Uso:
 *   frida -U -f com.qcymall.googleearphonesetup -l qcy-ble-sniffer.js --no-pause
 *
 * Para dispositivos não-root: usa frida-server no Android.
 */

console.log("[*] QCY BLE Sniffer loaded");

// Hook em BluetoothGatt.writeCharacteristic
const BluetoothGatt = Java.use("android.bluetooth.BluetoothGatt");
BluetoothGatt.writeCharacteristic.implementation = function(characteristic) {
    const uuid = characteristic.getUuid().toString();
    const value = characteristic.getValue();
    const hex = Array.from(value)
        .map(b => b.toString(16).padStart(2, '0'))
        .join(' ');
    
    console.log(`[BLE WRITE] UUID: ${uuid}`);
    console.log(`[BLE WRITE] Value (${value.length} bytes): ${hex}`);
    
    // salvar em arquivo para análise posterior?
    // send to host via send() etc.
    
    return this.writeCharacteristic(characteristic);
};

// Hook nas classes do SDK QCY
const UteBleConnection = Java.use("com.yc.nadalsdk.ble.open.UteBleConnection");
if (UteBleConnection) {
    // sendDataToJlDevice([B)
    UteBleConnection.sendDataToJlDevice.implementation = function(bytes) {
        const hex = Array.from(bytes)
            .map(b => b.toString(16).padStart(2, '0'))
            .join(' ');
        console.log(`[QCY SDK] sendDataToJlDevice: ${hex}`);
        
        try {
            // Log stack para ver onde foi chamado
            console.log(this.java.lang.Exception.getStackTrace());
        } catch(e) {}
        
        return this.sendDataToJlDevice(bytes);
    };
}

// Hook em Lutefor/utefor;->utedo([B)V (método de processamento interno)
const UteforUtefor = Java.use("Lutefor/utefor");
if (UteforUtefor) {
    UteforUtefor.utedo.implementation = function(bytes) {
        const hex = Array.from(bytes)
            .map(b => b.toString(16).padStart(2, '0'))
            .join(' ');
        console.log(`[QCY INTERNAL] utedo([B]): ${hex}`);
        return this.utedo(bytes);
    };
}

console.log("[*] Hooks instalados. Abra o app e use as funções para capturar.");