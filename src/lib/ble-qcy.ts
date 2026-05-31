/**
 * QCY BLE Controller - cliente completo para fones QCY
 * Usa BlueZ via D-Bus (dbus-next) para comunicação GATT
 */

import { BlueZGatt } from './bluez-gatt.js';
import {
  QCYProtocol,
  QCYCommand,
  ANCSettingMode,
  LowLatencyMode,
  MusicControl,
  decodeBattery,
  decodeVersion,
} from './ble-qcy-protocol.js';

export class QCYController {
  private gatt: BlueZGatt;
  private connected: boolean = false;
  private notifyQueue: Uint8Array[] = [];

  constructor() {
    this.gatt = new BlueZGatt();
  }

  async connect(mac: string): Promise<void> {
    await this.gatt.connect();
    await this.gatt.connectDevice(mac);
    this.connected = true;
    console.log('✅ QCY conectado');
  }

  async disconnect(): Promise<void> {
    if (this.connected) {
      await this.gatt.disconnectDevice();
      await this.gatt.disconnect();
      this.connected = false;
    }
  }

  async sendCommand(cmd: QCYCommand, params: number[] = []): Promise<void> {
    if (!this.connected) throw new Error('Não conectado');

    const packet = QCYProtocol.buildPacket(cmd, params);
    // Escrever na characteristic de comando (00001001)
    await this.gatt.writeCharacteristic('00001001-0000-1000-8000-00805f9b34fb', packet);
  }

  // ---------- Comandos de alto nível ----------

  async setANCmode(mode: ANCSettingMode, subScene?: number, noiseValue?: number): Promise<void> {
    if (mode === ANCSettingMode.TRANSPARENCY) {
      const scene = subScene || 1;
      const nv = noiseValue || 0x80;
      await this.sendCommand(QCYCommand.ANCSetting, [0x04, scene, nv]);
    } else if (mode === ANCSettingMode.ANC) {
      const scene = subScene || 1;
      const nv = noiseValue || 0x80;
      await this.sendCommand(QCYCommand.ANCSetting, [0x02, scene, nv]);
    } else if (mode === ANCSettingMode.OUTDOOR) {
      await this.sendCommand(QCYCommand.ANCSetting, [0x03, 1, 0x80]);
    } else {
      await this.sendCommand(QCYCommand.ANCSetting, [0x00, 0x00, 0x00]);
    }
  }

  async setVolume(left: number, right: number): Promise<void> {
    left = Math.max(0, Math.min(100, left));
    right = Math.max(0, Math.min(100, right));
    await this.sendCommand(QCYCommand.Volume, [left, right, 0x00]);
  }

  async setGameMode(enabled: boolean): Promise<void> {
    await this.sendCommand(QCYCommand.LowLatency, [enabled ? LowLatencyMode.ENABLE : LowLatencyMode.DISABLE]);
  }

  async setInEarDetection(enable: boolean): Promise<void> {
    await this.sendCommand(QCYCommand.InEarDetection, [enable ? 0x01 : 0x02]);
  }

  async musicControl(action: MusicControl): Promise<void> {
    await this.sendCommand(QCYCommand.MusicControl, [action]);
  }

  async requestBattery(): Promise<{ left: number; right: number; cas?: number }> {
    await this.sendCommand(QCYCommand.RequestData, [QCYCommand.Battery]);
    return this.waitForResponse(QCYCommand.Battery, 3);
  }

  async requestVersion(): Promise<string> {
    await this.sendCommand(QCYCommand.RequestData, [QCYCommand.Version]);
    const bytes = await this.waitForResponse(QCYCommand.Version, 6);
    return decodeVersion(bytes);
  }

  async readBatteryDirect(): Promise<{ left: number; right: number; cas?: number }> {
    const raw = await this.gatt.readCharacteristic('00000008-0000-1000-8000-00805f9b34fb');
    const decoded = decodeBattery(raw);
    return {
      left: decoded[0].level,
      right: decoded[1].level,
      cas: decoded[2]?.level,
    };
  }

  async readVersionDirect(): Promise<string> {
    const raw = await this.gatt.readCharacteristic('00000007-0000-1000-8000-00805f9b34fb');
    return decodeVersion(raw);
  }

  // ---------- Helpers para esperar respostas ----------

  private async waitForResponse(cmd: QCYCommand, minParams: number): Promise<Uint8Array> {
    const timeout = Date.now() + 5000;
    while (Date.now() < timeout) {
      const notif = this.notifyQueue.find((n) => n[0] === 0xFF && n[2] === cmd);
      if (notif) {
        const parsed = QCYProtocol.parseNotification(notif);
        if (parsed && parsed.params.length >= minParams) {
          this.notifyQueue = this.notifyQueue.filter((n) => n !== notif);
          return parsed.params;
        }
      }
      await new Promise((r) => setTimeout(r, 100));
    }
    throw new Error(`Timeout esperando resposta para cmd 0x${cmd.toString(16)}`);
  }

  // ---------- Stream de notificações ----------

  async *notifications(): AsyncIterable<{ cmd: QCYCommand; params: Uint8Array }> {
    const stream = await this.gatt.enableNotifications();
    for await (const data of stream) {
      const parsed = QCYProtocol.parseNotification(data);
      if (parsed) {
        this.notifyQueue.push(data);
        yield parsed;
      }
    }
  }
}
