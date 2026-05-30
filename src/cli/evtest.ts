#!/usr/bin/env bun

/**
 * QCY Control - EvTest
 * Captura e mapeia eventos AVRCP do dispositivo QCY
 */

import { EventEmitter } from 'events';
import { readFile, writeFile } from 'fs/promises';
import { existsSync } from 'fs';

interface EventMap {
  [key: number]: {
    code: string;
    description: string;
    value?: number;
  };
}

// Mapeamento parcial de códigos de teclas (do linux/input-event-codes.h)
const KEY_CODES: EventMap = {
  164: { code: 'PLAYPAUSE', description: 'play/pause' },
  165: { code: 'STOPCD', description: 'stop' },
  166: { code: 'NEXTSONG', description: 'next track' },
  167: { code: 'PREVIOUSSONG', description: 'previous track' },
  168: { code: 'VOLUMEUP', description: 'volume up' },
  169: { code: 'VOLUMEDOWN', description: 'volume down' },
  200: { code: 'MUTE', description: 'mute toggle' },
  // adicionar mais conforme descoberto
};

class EvTest extends EventEmitter {
  private devicePath: string;

  constructor(devicePath: string) {
    super();
    this.devicePath = devicePath;
  }

  async start(): Promise<void> {
    if (!existsSync(this.devicePath)) {
      throw new Error(`dispositivo não encontrado: ${this.devicePath}`);
    }

    console.log(`🎧 capturando eventos de ${this.devicePath}`);
    console.log('pressione botões no fone... (ctrl+c para parar)\n');

    // TODO: implementar leitura real de /dev/input/eventX
    // por enquanto, mock para desenvolvimento
    this.simulateEvents();
  }

  private simulateEvents(): void {
    const events = [
      { type: 'key', code: 164, value: 1 },
      { type: 'key', code: 164, value: 0 },
      { type: 'key', code: 166, value: 1 },
      { type: 'key', code: 166, value: 0 },
      { type: 'key', code: 168, value: 1 },
      { type: 'key', code: 168, value: 0 },
    ];

    let idx = 0;
    const interval = setInterval(() => {
      const ev = events[idx % events.length];
      this.emit('event', ev);
      idx++;
    }, 2000);
  }

  async saveMapping(mapping: Record<string, string>): Promise<void> {
    const configDir = Bun.expand('~/.config/qcy');
    if (!existsSync(configDir)) {
      await Bun.write(configDir, '');
    }
    await writeFile(`${configDir}/mappings.json`, JSON.stringify(mapping, null, 2));
    console.log('✅ mapeamento salvo em ~/.config/qcy/mappings.json');
  }
}

// execução direta
if (import.meta.main) {
  const devicePath = Bun.argv[2] || '/dev/input/event19';
  const tester = new EvTest(devicePath);

  tester.on('event', (ev: any) => {
    const keyInfo = KEY_CODES[ev.code] || { code: `KEY_${ev.code}`, description: 'desconhecido' };
    console.log(`[${ev.value === 1 ? 'press  ' : 'release']} ${keyInfo.code} - ${keyInfo.description}`);
  });

  tester.start().catch(console.error);
}

export { EvTest, KEY_CODES };
