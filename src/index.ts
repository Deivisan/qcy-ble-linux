#!/usr/bin/env bun

/**
 * QCY Control - Sistema de Controle para Fones QCY no Linux
 * Missão: Provide robust control over QCY H3S/H2S devices on Linux
 * Stack: Bun + TypeScript + PipeWire + BlueZ + AVRCP
 */

import { Command } from 'commander';
import chalk from 'chalk';
import { version } from '../package.json' assert { type: 'json' };
import { printStatus } from './cli/status.js';
import { toA2DP, toHFP, toggle } from './cli/profile.js';

const program = new Command();

program
  .name('qcy-control')
  .description('sistema completo de controle para fones QCY no linux')
  .version(version);

// subcomandos
program
  .command('evtest')
  .description('mapear eventos dos botões do fone via evdev')
  .option('-d, --device <path>', 'caminho do dispositivo evdev', '/dev/input/event19')
  .action(async (options) => {
    console.log(chalk.cyan('🔍 iniciando mapeamento de eventos avrcp...'));
    // TODO: implementar captura de eventos
  });

program
  .command('status')
  .description('verificar status atual do dispositivo (pipewire, bluez, perfil)')
  .action(async () => {
    await printStatus();
  });

program
  .command('profile <profile>')
  .description('alternar perfil de áudio (a2dp ou hfp)')
  .option('--device <mac>', 'endereço bluetooth do fone', '84:AC:60:05:55:2C')
  .option('--force, -f', 'forçar mudança mesmo já no perfil')
  .action(async (profile, options) => {
    switch (profile) {
      case 'a2dp':
        await toA2DP({ deviceMac: options.device, force: options.force });
        break;
      case 'hfp':
        await toHFP({ deviceMac: options.device, force: options.force });
        break;
      default:
        console.error(chalk.red('erro: perfil deve ser "a2dp" ou "hfp"'));
        process.exit(1);
    }
  });

program
  .command('toggle')
  .description('alternar automaticamente entre a2dp e hfp')
  .option('--device <mac>', 'endereço bluetooth do fone', '84:AC:60:05:55:2C')
  .action(async (options) => {
    await toggle({ deviceMac: options.device });
  });

program
  .command('daemon')
  .description('iniciar daemon de automações')
  .option('-c, --config <path>', 'arquivo de configuração', '~/.config/qcy/config.json')
  .action(async (options) => {
    console.log(chalk.cyan('🔄 iniciando daemon de automações...'));
    // TODO: implementar daemon
  });

program
  .command('gui')
  .description('iniciar interface gráfica de configuração')
  .option('--port <port>', 'porta do servidor web', '3000')
  .action(async (options) => {
    console.log(chalk.cyan('🖥️  iniciando interface web...'));
    // TODO: implementar GUI (web-based?)
  });

program.parse();
