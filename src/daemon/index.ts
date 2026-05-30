#!/usr/bin/env bun

/**
 * QCY Control - Daemon de Automações
 * Escuta eventos dos botões e executa ações configuradas
 */

import { existsSync, readFile, writeFile, mkdir } from 'fs/promises';
import { join } from 'path';
import { EventEmitter } from 'events';
import { exec } from 'child_process';
import { promisify } from 'util';
import chalk from 'chalk';

const execAsync = promisify(exec);

interface Action {
  type: 'command' | 'mpris' | 'profile' | 'custom';
  value: string;
}

interface Mapping {
  [key: string]: Action;
}

interface Config {
  device: string;
  mappings: Mapping;
  autoReconnect?: boolean;
  debug?: boolean;
}

const CONFIG_DIR = Bun.expand('~/.config/qcy');
const CONFIG_PATH = join(CONFIG_DIR, 'config.json');
const DEFAULT_CONFIG: Config = {
  device: '/dev/input/event19',
  mappings: {
    play_pause: { type: 'mpris', value: 'playpause' },
    next: { type: 'mpris', value: 'next' },
    previous: { type: 'mpris', value: 'previous' },
    volume_up: { type: 'command', value: 'pactl set-sink-volume @DEFAULT_SINK@ +5%' },
    volume_down: { type: 'command', value: 'pactl set-sink-volume @DEFAULT_SINK@ -5%' },
  },
  debug: false,
};

async function loadConfig(): Promise<Config> {
  try {
    if (!existsSync(CONFIG_PATH)) {
      await ensureConfig();
    }
    const raw = await readFile(CONFIG_PATH, 'utf-8');
    return { ...DEFAULT_CONFIG, ...JSON.parse(raw) };
  } catch (err) {
    console.error(chalk.red('erro ao carregar config:'), err);
    return DEFAULT_CONFIG;
  }
}

async function ensureConfig(): Promise<void> {
  await mkdir(CONFIG_DIR, { recursive: true });
  await writeFile(CONFIG_PATH, JSON.stringify(DEFAULT_CONFIG, null, 2));
  console.log(chalk.green('✅ config criada em'), CONFIG_PATH);
}

async function executeAction(action: Action): Promise<void> {
  const log = (...args: any[]) => console.log(chalk.gray('[daemon]'), ...args);

  switch (action.type) {
    case 'command':
      log('executando comando:', action.value);
      const { stdout, stderr } = await execAsync(action.value);
      if (stdout) log('stdout:', stdout.trim());
      if (stderr) log('stderr:', stderr.trim());
      break;

    case 'mpris':
      log('comando mpris:', action.value);
      await execAsync(`playerctl ${action.value}`);
      break;

    case 'profile':
      log('mudando perfil para:', action.value);
      await execAsync(`bun run src/cli/profile.ts ${action.value}`);
      break;

    case 'custom':
      log('ação custom:', action.value);
      // TODO: permitir chamar funções custom do config
      break;

    default:
      log(chalk.yellow(`ação desconhecida: ${action.type}`));
  }
}

class Daemon extends EventEmitter {
  private config: Config;
  private running: boolean = false;

  constructor(config: Config) {
    super();
    this.config = config;
  }

  async start(): Promise<void> {
    console.log(chalk.cyan('🔄 iniciando daemon qcy-control...\n'));
    console.log(chalk.gray('config:'), CONFIG_PATH);
    console.log(chalk.gray('device:'), this.config.device);
    console.log(chalk.gray('mappings:'), Object.keys(this.config.mappings).join(', '));

    try {
      // importar evtest-real dinamicamente para não bloquear start se falhar
      const { RealEvTest } = await import('./evtest-real.js');

      const tester = new RealEvTest(this.config.device);

      tester.on('key', async (ev) => {
        const name = this.lookupKeyName(ev.code);
        if (this.config.debug) {
          console.log(chalk.dim(`[evento] ${name} (code=${ev.code}, value=${ev.value})`));
        }

        if (ev.value === 1 && name && this.config.mappings[name]) {
          await executeAction(this.config.mappings[name]);
        }
      });

      tester.on('error', (err: any) => {
        console.error(chalk.red('erro no evtest:'), err.message);
      });

      await tester.start();
      this.running = true;

      // manter processo vivo
      await this.keepAlive();

    } catch (err: any) {
      console.error(chalk.red('falha ao iniciar daemon:'), err.message);
      console.log(chalk.yellow('dica: Verifique se o dispositivo existe e se você tem permissões.'));
      process.exit(1);
    }
  }

  private lookupKeyName(code: number): string | null {
    const keyMap: Record<number, string> = {
      164: 'play_pause',
      166: 'next',
      167: 'previous',
      168: 'volume_up',
      169: 'volume_down',
    };
    return keyMap[code] || null;
  }

  private async keepAlive(): Promise<void> {
    return new Promise(() => {
      //Never resolves unless stopped
    });
  }

  stop(): void {
    this.running = false;
    console.log(chalk.yellow('🛑 daemon parando...'));
    process.exit(0);
  }
}

// execução direta
if (import.meta.main) {
  const config = await loadConfig();
  const daemon = new Daemon(config);

  process.on('SIGINT', () => daemon.stop());
  process.on('SIGTERM', () => daemon.stop());

  await daemon.start();
}
