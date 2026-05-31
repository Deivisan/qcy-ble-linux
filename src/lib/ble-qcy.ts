/**
 * QCY BLE Client via CLI (gdbus + bluetoothctl)
 * Não requiere módulos nativos — puro TypeScript/Bun
 */

import { exec } from 'child_process';
import { promisify } from 'util';
const execAsync = promisify(exec);

export class QCYBle {
  private mac: string = '';
  private connected = false;

  // UUIDs (formato short)
  private static SERVICE_UUID = '0000a001';
  private static CMD_UUID = '00001001';
  private static NOTIFY_UUID = '00001002';
  private static BATTERY_UUID = '00000008';
  private static VERSION_UUID = '00000007';
  private static CCCD_UUID = '00002902';

  async connect(mac: string): Promise<void> {
    this.mac = mac;
    await this.ensureConnected();
    this.connected = true;
    console.log('✅ QCY conectado (via CLI)');
  }

  async disconnect(): Promise<void> {
    this.connected = false;
  }

  isConnected(): boolean {
    return this.connected;
  }

  private async ensureConnected(): Promise<void> {
    await execAsync('bluetoothctl power on').catch(() => {});
    await execAsync(`bluetoothctl connect ${this.mac}`).catch(async (e) => {
      const out = await execAsync(`bluetoothctl info ${this.mac}`).then(r => r.stdout);
      if (!out.includes('Connected: yes')) throw e;
    });
    await new Promise(r => setTimeout(r, 1000));
  }

  private async getCharPath(uuid: string): Promise<string> {
    const escaped = this.mac.replace(/:/g, '_');
    const base = `/org/bluez/hci0/dev_${escaped}`;
    // Tenta caminhos padrão
    const candidates = [
      `${base}/service0000A001/char${uuid}`,
      `${base}/service0000a001/char${uuid}`,
      `${base}/service00001001/char${uuid}`, // caso service diferente
    ];
    // Para battery/version, o service pode ser diferente? Mas documentação diz service0000A001.
    // Retornar o primeiro candidato e deixar write falhar se não existir.
    return candidates[0];
  }

  private staticService(): string {
    return 'service0000A001';
  }

  async sendCommand(cmd: number, params: number[] = []): Promise<void> {
    const body: number[] = [cmd, params.length, ...params];
    const packet = new Uint8Array(2 + body.length);
    packet[0] = 0xFF;
    packet[1] = body.length;
    packet.set(body, 2);
    const hex = Buffer.from(packet).toString('hex').toUpperCase();
    await this.writeByUUID(this.CMD_UUID, hex);
  }

  private async writeByUUID(uuid: string, hex: string): Promise<void> {
    const path = await this.getCharPath(uuid);
    const cmd = `gdbus call --session --dest org.bluez --object-path ${path} --method org.bluez.GattCharacteristic1.WriteValue "['${hex}']" "{}"`;
    await execAsync(cmd, { timeout: 5000 });
  }

  async readBattery(): Promise<{ left: number; right: number; case?: number }> {
    const path = await this.getCharPath(this.BATTERY_UUID);
    const cmd = `gdbus call --session --dest org.bluez --object-path ${path} --method org.bluez.GattCharacteristic1.ReadValue "{}"`;
    const { stdout } = await execAsync(cmd, { timeout: 5000 });
    const match = stdout.match(/\\([0-9A-F]{2})/gi);
    if (!match) throw new Error('Falha ler battery');
    const bytes = match.map(m => parseInt(m, 16));
    const parse = (b: number) => b & 0x7F;
    return {
      left: parse(bytes[0]),
      right: parse(bytes[1]),
      case: bytes[2] ? parse(bytes[2]) : undefined,
    };
  }

  async readVersion(): Promise<any> {
    const path = await this.getCharPath(this.VERSION_UUID);
    const cmd = `gdbus call --session --dest org.bluez --object-path ${path} --method org.bluez.GattCharacteristic1.ReadValue "{}"`;
    const { stdout } = await execAsync(cmd, { timeout: 5000 });
    const match = stdout.match(/\\([0-9A-F]{2})/gi);
    if (!match) throw new Error('Falha ler version');
    const bytes = match.map(m => parseInt(m, 16));
    if (bytes.length === 3) {
      return { major: bytes[0], minor: bytes[1], patch: bytes[2] };
    } else if (bytes.length >= 6) {
      return {
        left: { major: bytes[0], minor: bytes[1], patch: bytes[2] },
        right: { major: bytes[3], minor: bytes[4], patch: bytes[5] },
      };
    }
    return { major: 0, minor: 0, patch: 0 };
  }

  async setVolume(left: number, right: number): Promise<void> {
    await this.sendCommand(0x08, [left, right, 0]);
  }

  async setANCMode(mode: number): Promise<void> {
    await this.sendCommand(0x0C, [mode]);
  }

  async setANCSetting(mode: number, subScene: number, noiseValue: number): Promise<void> {
    await this.sendCommand(0x17, [mode, subScene, noiseValue]);
  }

  async setLowLatency(enabled: boolean): Promise<void> {
    await this.sendCommand(0x09, [enabled ? 1 : 2]);
  }

  async enableNotifications(): Promise<void> {
    const path = await this.getCharPath(this.NOTIFY_UUID);
    const cccdPath = `${path}/desc00002902-0000-1000-8000-00805f9b34fb`;
    await execAsync(`gdbus call --session --dest org.bluez --object-path ${cccdPath} --method org.bluez.GattDescriptor1.WriteValue "['0100']" "{}"`);
    await execAsync(`gdbus call --session --dest org.bluez --object-path ${path} --method org.bluez.GattCharacteristic1.StartNotify`);
    console.log('Notificações ativadas');
  }

  // Aliases para compatibilidade com CLI existente
  async requestBattery(): Promise<{ left: number; right: number; case?: number }> {
    return this.readBattery();
  }

  async requestVersion(): Promise<any> {
    return this.readVersion();
  }

  async musicControl(action: number): Promise<void> {
    await this.sendCommand(0x04, [action]);
  }

  async musicPlay(): Promise<void> { await this.musicControl(1); }
  async musicPause(): Promise<void> { await this.musicControl(2); }
  async musicNext(): Promise<void> { await this.musicControl(3); }
  async musicPrev(): Promise<void> { await this.musicControl(4); }

  async notifications(): AsyncIterable<any> {
    return {
      [Symbol.asyncIterator]: async function* () {}
    };
  }
}

// Classe legada para compatibilidade
export class QCYController extends QCYBle {}

// Factory
export function createQCYBle(): QCYBle {
  return new QCYBle();
}
