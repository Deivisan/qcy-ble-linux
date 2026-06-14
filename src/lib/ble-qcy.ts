/**
 * QCY Unified Client — now prefers the proven SPP/RFCOMM path.
 *
 * This is the drop-in replacement for the old GATT-only QCYBle.
 * It keeps the same public API (connect, setANCMode, setVolume, setLowLatency, etc.)
 * but actually works on the QCY H3S because it uses the working C sender under the hood.
 *
 * Cable must be removed. Bluetooth must be connected.
 */

import * as spp from './spp/qcy-spp-exec.js';

export class QCYBle {
  private mac: string = '';
  private connected = false;

  async connect(mac: string): Promise<void> {
    this.mac = mac;
    // For SPP we don't need to "connect" in the GATT sense — we just verify BT is up.
    // The actual RFCOMM connect happens per-packet inside the C binary.
    const { exec } = await import('child_process');
    const { promisify } = await import('util');
    const execAsync = promisify(exec);

    await execAsync('bluetoothctl power on').catch(() => {});
    const { stdout } = await execAsync(`bluetoothctl info ${mac}`).catch(() => ({ stdout: '' }));
    if (!stdout.includes('Connected: yes')) {
      throw new Error(`QCY ${mac} not connected via Bluetooth. Remove the cable and connect first.`);
    }
    this.connected = true;
    console.log(`✅ QCY ${mac} — controle via SPP/RFCOMM (GATT vendor não exposto)`);
  }

  async disconnect(): Promise<void> {
    this.connected = false;
  }

  isConnected(): boolean {
    return this.connected;
  }

  // === Feature control (delegated to working SPP binary) ===

  async setANCMode(mode: number): Promise<void> {
    const r = await spp.setANCMode(mode);
    if (!r.success) throw new Error(`SPP ANC failed: ${r.stderr}`);
    console.log(`[SPP] ANC mode ${mode} enviado`);
  }

  async setANCSetting(mode: number, subScene: number, noiseValue: number): Promise<void> {
    const r = await spp.setANCAdvanced(mode, subScene, noiseValue);
    if (!r.success) throw new Error(`SPP ANC advanced failed: ${r.stderr}`);
    console.log(`[SPP] ANC advanced ${mode},${subScene},${noiseValue} enviado`);
  }

  async setLowLatency(enabled: boolean): Promise<void> {
    const r = await spp.setLowLatency(enabled);
    if (!r.success) throw new Error(`SPP low latency failed: ${r.stderr}`);
    console.log(`[SPP] LowLatency/Game ${enabled ? 'ON' : 'OFF'} enviado`);
  }

  async setVolume(left: number, right: number): Promise<void> {
    const r = await spp.setVolume(left, right);
    if (!r.success) throw new Error(`SPP volume failed: ${r.stderr}`);
    console.log(`[SPP] Volume L${left} R${right} enviado`);
  }

  async setLDAC(enabled: boolean): Promise<void> {
    const r = await spp.setLDAC(enabled);
    if (!r.success) throw new Error(`SPP LDAC failed: ${r.stderr}`);
    console.log(`[SPP] LDAC ${enabled ? 'ON' : 'OFF'} enviado (pode reiniciar o fone)`);
  }

  // Music control (same numbers as before)
  async musicControl(action: number): Promise<void> {
    const r = await spp.musicControl(action);
    if (!r.success) throw new Error(`SPP music failed: ${r.stderr}`);
  }

  async musicPlay(): Promise<void> { await this.musicControl(1); }
  async musicPause(): Promise<void> { await this.musicControl(2); }
  async musicNext(): Promise<void> { await this.musicControl(3); }
  async musicPrev(): Promise<void> { await this.musicControl(4); }

  // Battery and version still come from standard BlueZ (no vendor service needed)
  async readBattery(): Promise<{ left: number; right: number; case?: number }> {
    const { exec } = await import('child_process');
    const { promisify } = await import('util');
    const execAsync = promisify(exec);
    const { stdout } = await execAsync(`bluetoothctl info ${this.mac}`);
    const m = stdout.match(/Battery Percentage:\s*0x[0-9A-Fa-f]+\s*\((\d+)\)/);
    const pct = m ? parseInt(m[1], 10) : 0;
    return { left: pct, right: pct };
  }

  async readVersion(): Promise<any> {
    // Version is not easily readable without the vendor char; return placeholder for now.
    return { note: 'version read requires vendor GATT (not exposed) or SPP response parsing' };
  }

  // Legacy aliases the CLI still calls
  async requestBattery() { return this.readBattery(); }
  async requestVersion() { return this.readVersion(); }

  // Notifications not implemented over SPP yet (would require a reader thread on the RFCOMM socket)
  async notifications(): AsyncIterable<any> {
    return {
      [Symbol.asyncIterator]: async function* () {
        // no-op for now
      },
    };
  }
}

// Back-compat exports
export { QCYBle as QCYController };
export function createQCYBle() { return new QCYBle(); }

// Quick helpers (still useful)
export async function quickANC(mac: string, on: boolean) {
  const q = new QCYBle();
  await q.connect(mac);
  await q.setANCMode(on ? 1 : 0);
  console.log(`ANC ${on ? 'ON' : 'OFF'} via SPP`);
}

export async function quickGameMode(mac: string, on: boolean) {
  const q = new QCYBle();
  await q.connect(mac);
  await q.setLowLatency(on);
  console.log(`Game ${on ? 'ON' : 'OFF'} via SPP`);
}

export async function quickVolume(mac: string, left: number, right: number) {
  const q = new QCYBle();
  await q.connect(mac);
  await q.setVolume(left, right);
  console.log(`Volume ${left}/${right} via SPP`);
}
