#!/usr/bin/env bun

/**
 * QCY Control - EvTest com leitura real de eventos evdev
 * Captura códigos de teclas do dispositivo input
 */

import { EventEmitter } from 'events';
import { open } from 'fs/promises';
import { existsSync } from 'fs';
import { Buffer } from 'buffer';

// Estrutura de evento evdev (conforme linux/input.h)
interface EvdevEvent {
  tv_sec: bigint;
  tv_usec: bigint;
  type: number;
  code: number;
  value: number;
}

// Constantes evdev (trecho)
const EV_KEY = 1;

class RealEvTest extends EventEmitter {
  private devicePath: string;
  private fd: number | null = null;
  private running: boolean = false;

  constructor(devicePath: string) {
    super();
    this.devicePath = devicePath;
  }

  async start(): Promise<void> {
    if (!existsSync(this.devicePath)) {
      throw new Error(`dispositivo não encontrado: ${this.devicePath}`);
    }

    // requer sudo ou permissões udev adequadas
    this.fd = await open(this.devicePath, 'r');
    this.running = true;

    console.log(`🎧 capturando eventos reais de ${this.devicePath}`);
    console.log('pressione botões no fone... (ctrl+c para parar)\n');

    this.readLoop();
  }

  private readLoop(): void {
    if (!this.fd) return;

    const buffer = new ArrayBuffer(24); // sizeof(struct input_event)

    const reader = async () => {
      while (this.running && this.fd) {
        try {
          const { bytesRead } = await Bun.write(this.fd, buffer);
          if (bytesRead === 24) {
            const ev = this.parseEvent(buffer);
            if (ev.type === EV_KEY) {
              this.emit('key', ev);
            }
          }
        } catch (err) {
          if (this.running) console.error('erro leitura evdev:', err);
          break;
        }
      }
    };

    reader();
  }

  private parseEvent(buffer: ArrayBuffer): EvdevEvent {
    const view = new DataView(buffer);
    return {
      tv_sec: BigInt(view.getUint32(0, true)),
      tv_usec: BigInt(view.getUint32(4, true)),
      type: view.getUint16(8, true),
      code: view.getUint16(10, true),
      value: view.getInt32(12, true),
    };
  }

  stop(): void {
    this.running = false;
    if (this.fd) {
      this.fd.close();
      this.fd = null;
    }
  }
}

// mapeamento know-key codes
export const KEY_MAP: Record<number, string> = {
  164: 'play_pause',
  165: 'stop',
  166: 'next',
  167: 'previous',
  168: 'volume_up',
  169: 'volume_down',
  200: 'mute',
  115: 'power',      // power key
  226: 'phone',      // phone call
  227: 'end_call',   // end call
};

if (import.meta.main) {
  const devicePath = process.argv[2] || '/dev/input/event19';
  const tester = new RealEvTest(devicePath);

  tester.on('key', (ev) => {
    const name = KEY_MAP[ev.code] || `key_${ev.code}`;
    const action = ev.value === 1 ? 'press' : ev.value === 0 ? 'release' : 'repeat';
    console.log(`[${action}] ${name} (code=${ev.code})`);
  });

  process.on('SIGINT', () => {
    tester.stop();
    process.exit(0);
  });

  tester.start().catch((err) => {
    console.error(chalk.red('erro:'), err.message);
    console.log(chalk.yellow('dica: Execute com sudo ou ajuste udev rules para permitir acesso.'));
    process.exit(1);
  });
}
