#!/usr/bin/env bun

/**
 * QCY Control - Comandos BLE
 * Controle avançado via protocolo BLE (baseado em Quicky)
 */

import { QCYController } from '../lib/ble-qcy.js';
import { ANCSettingMode, MusicControl } from '../lib/ble-qcy-protocol.js';
import chalk from 'chalk';

interface CLIOptions {
  mac?: string;
}

async function getMAC(): Promise<string> {
  // tentar da config, ou fallback
  const defaultMac = '84:AC:60:05:55:2C'; // MAC do seu QCY H3S
  return process.env.QCY_BLE_MAC || defaultMac;
}

async function cmdConnect(options: CLIOptions): Promise<void> {
  const mac = options.mac || await getMAC();
  const ctrl = new QCYController();

  try {
    console.log(chalk.cyan(`🔗 conectando a ${mac} via BLE...`));
    await ctrl.connect(mac);
    console.log(chalk.green('✅ conectado!'));

    // ler bateria
    const bat = await ctrl.requestBattery();
    console.log(chalk.cyan('🔋 bateria:'), `L=${bat.left}% R=${bat.right}%`, bat.cas ? `C=${bat.cas}%` : '');

    // ler versão
    const ver = await ctrl.requestVersion();
    console.log(chalk.cyan('📟 versão:'), ver);

    console.log(chalk.yellow('\nComandos BLE disponíveis:'));
    console.log('  ble anc <mode>    [on|off|transparency|anc]');
    console.log('  ble volume <L> <R>');
    console.log('  ble latency <on|off>');
    console.log('  ble music <play|pause|next|prev>');
    console.log('  ble battery');
    console.log('  ble version');
    console.log('\nPressione Ctrl+C para sair.');

    // escutar notificações (opcional)
    for await (const ev of ctrl.notifications()) {
      console.log(chalk.gray('[notif]'), `cmd=0x${ev.cmd.toString(16)}`, 'params=', Array.from(ev.params));
    }
  } catch (err: any) {
    console.error(chalk.red('erro:'), err.message);
    process.exit(1);
  }
}

async function cmdANC(modeStr: string): Promise<void> {
  const mac = await getMAC();
  const ctrl = new QCYController();
  await ctrl.connect(mac);

  let mode: ANCSettingMode;
  switch (modeStr.toLowerCase()) {
    case 'on':
    case 'anc':
      mode = ANCSettingMode.ANC;
      break;
    case 'off':
      mode = ANCSettingMode.OFF;
      break;
    case 'transparency':
      mode = ANCSettingMode.TRANSPARENCY;
      break;
    default:
      console.error(chalk.red('modo inválido. Use: on|off|transparency|anc'));
      process.exit(1);
  }

  await ctrl.setANCmode(mode);
  console.log(chalk.green(`✅ ANC definido para: ${modeStr}`));
  await ctrl.disconnect();
}

async function cmdVolume(left: number, right: number): Promise<void> {
  const mac = await getMAC();
  const ctrl = new QCYController();
  await ctrl.connect(mac);
  await ctrl.setVolume(left, right);
  console.log(chalk.green(`✅ volume: L=${left}% R=${right}%`));
  await ctrl.disconnect();
}

async function cmdLatency(on: boolean): Promise<void> {
  const mac = await getMAC();
  const ctrl = new QCYController();
  await ctrl.connect(mac);
  await ctrl.setGameMode(on);
  console.log(chalk.green(`✅ game mode: ${on ? 'ON' : 'OFF'}`));
  await ctrl.disconnect();
}

async function cmdMusic(action: string): Promise<void> {
  const mac = await getMAC();
  const ctrl = new QCYController();
  await ctrl.connect(mac);

  let cmd: MusicControl;
  switch (action.toLowerCase()) {
    case 'play':
      cmd = MusicControl.PLAY;
      break;
    case 'pause':
      cmd = MusicControl.PAUSE;
      break;
    case 'next':
      cmd = MusicControl.NEXT;
      break;
    case 'prev':
      cmd = MusicControl.PREV;
      break;
    default:
      console.error(chalk.red('ação inválida. Use: play|pause|next|prev'));
      process.exit(1);
  }

  await ctrl.musicControl(cmd);
  console.log(chalk.green(`✅ música: ${action}`));
  await ctrl.disconnect();
}

async function cmdBattery(): Promise<void> {
  const mac = await getMAC();
  const ctrl = new QCYController();
  await ctrl.connect(mac);
  const bat = await ctrl.requestBattery();
  console.log(chalk.cyan('🔋 Bateria:'));
  console.log(`  Esquerda: ${bat.left}%${bat.left > 0 ? (bat.left < 20 ? ' (baixa)' : '') : ''}`);
  console.log(`  Direita:  ${bat.right}%`);
  if (bat.cas !== undefined) {
    console.log(`  Case:     ${bat.cas}%`);
  }
  await ctrl.disconnect();
}

async function cmdVersion(): Promise<void> {
  const mac = await getMAC();
  const ctrl = new QCYController();
  await ctrl.connect(mac);
  const ver = await ctrl.requestVersion();
  console.log(chalk.cyan('📟 Versão firmware:'), ver);
  await ctrl.disconnect();
}

// ---------------------- main ----------------------

const args = process.argv.slice(2);
const command = args[0];

if (!command || command === 'help') {
  console.log(`
🔒 QCY BLE Control (protocolo Quicky)

Uso:
  bun run src/cli/ble.ts <comando> [opções]

Comandos:
  connect [--mac <MAC>]
    Conecta ao fone e inicia shell interativo (simulado)

  anc <mode>
    Modo ANC: on|off|transparency|anc

  volume <L> <R>
    Define volume left/right (0-100)

  latency <on|off>
    Modo baixa latência (game mode)

  music <play|pause|next|prev>
    Controle de música

  battery
    Ler nível de bateria

  version
    Ler versão do firmware

Exemplos:
  bun run src/cli/ble.ts anc transparency
  bun run src/cli/ble.ts volume 80 80
  bun run src/cli/ble.ts latency on

* MAC address padrão: 84:AC:60:05:55:2C
* Para alterar: export QCY_BLE_MAC=XX:XX:XX:XX:XX:XX
`);
  process.exit(0);
}

switch (command) {
  case 'connect':
    await cmdConnect({ mac: args.find((a) => a === '--mac') ? args[args.indexOf('--mac') + 1] : undefined });
    break;
  case 'anc':
    if (!args[1]) {
      console.error(chalk.red('erro: informe o modo (on|off|transparency|anc)'));
      process.exit(1);
    }
    await cmdANC(args[1]);
    break;
  case 'volume':
    if (!args[1] || !args[2]) {
      console.error(chalk.red('erro: informe left e right (0-100)'));
      process.exit(1);
    }
    await cmdVolume(parseInt(args[1], 10), parseInt(args[2], 10));
    break;
  case 'latency':
    if (!args[1]) {
      console.error(chalk.red('erro: informe on|off'));
      process.exit(1);
    }
    await cmdLatency(args[1] === 'on');
    break;
  case 'music':
    if (!args[1]) {
      console.error(chalk.red('erro: informe ação (play|pause|next|prev)'));
      process.exit(1);
    }
    await cmdMusic(args[1]);
    break;
  case 'battery':
    await cmdBattery();
    break;
  case 'version':
    await cmdVersion();
    break;
  default:
    console.error(chalk.red(`comando desconhecido: ${command}`));
    process.exit(1);
}
