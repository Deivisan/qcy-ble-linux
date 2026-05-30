#!/usr/bin/env bun

/**
 * QCY Control - Status Checker
 * Consulta PipeWire, BlueZ e perfil ativo do QCY
 */

import { exec } from 'child_process';
import { promisify } from 'util';
import { readFile } from 'fs/promises';
import { existsSync } from 'fs';
import chalk from 'chalk';

const execAsync = promisify(exec);

interface DeviceStatus {
  connected: boolean;
  profile: string | null;
  source: string | null;
  sink: string | null;
  bluetooth_card: string | null;
  battery?: number;
}

async function getPactlInfo(): Promise<any> {
  try {
    const { stdout } = await execAsync('pactl list cards');
    return stdout;
  } catch {
    return '';
  }
}

async function getPipeWireStatus(): Promise<any> {
  try {
    const { stdout } = await execAsync('wpctl status');
    return stdout;
  } catch {
    return '';
  }
}

async function checkBluetoothctl(): Promise<any> {
  try {
    const { stdout } = await execAsync('bluetoothctl info 84:AC:60:05:55:2C');
    return stdout;
  } catch {
    return null;
  }
}

function parseCardInfo(output: string): Partial<DeviceStatus> {
  const status: Partial<DeviceStatus> = {};

  // detecta perfil ativo
  const profileMatch = output.match(/Active Profile:\s*(.+)/);
  if (profileMatch) {
    status.profile = profileMatch[1].trim();
  }

  // detecta nome do card
  const cardMatch = output.match(/Name:\s+(bluez_card\.[\d_AC:]+)/);
  if (cardMatch) {
    status.bluetooth_card = cardMatch[1];
  }

  return status;
}

async function getStatus(): Promise<DeviceStatus> {
  const [pactlOutput, btInfo, pwStatus] = await Promise.all([
    getPactlInfo(),
    checkBluetoothctl(),
    getPipeWireStatus(),
  ]);

  const parsed = parseCardInfo(pactlOutput);

  return {
    connected: btInfo !== null,
    profile: parsed.profile,
    source: parsed.bluetooth_card ? `bluez_input.${parsed.bluetooth_card.split('.')[1]}` : null,
    sink: parsed.bluetooth_card ? `bluez_output.${parsed.bluetooth_card.split('.')[1]}` : null,
    bluetooth_card: parsed.bluetooth_card,
  };
}

async function printStatus(): Promise<void> {
  const status = await getStatus();

  console.log(chalk.bold('\n📊 Status do QCY H3S\n'));

  console.log(`${chalk.green('✔')} Bluetooth: ${status.connected ? chalk.green('conectado') : chalk.red('desconectado')}`);

  if (status.bluetooth_card) {
    console.log(`${chalk.cyan('ℹ')} Card: ${status.bluetooth_card}`);
  }

  if (status.profile) {
    const color = status.profile.includes('headset') ? chalk.yellow : chalk.cyan;
    console.log(`${color('▸')} Perfil ativo: ${color(status.profile)}`);
  } else {
    console.log(`${chalk.yellow('⚠')} Perfil: ${chalk.yellow('não detectado')}`);
  }

  if (status.source) {
    console.log(`${chalk.magenta('🔊')} Source: ${status.source}`);
  }

  if (status.sink) {
    console.log(`${chalk.blue('🔈')} Sink: ${status.sink}`);
  }

  // sugestão de comando para测试 do mic
  if (status.profile?.includes('headset')) {
    console.log(chalk.green('\n💡 Teste rápido do microfone:'));
    console.log(`   timeout 5 parecord --device=${status.source} /tmp/qcy-test.wav`);
  }

  console.log('');
}

if (import.meta.main) {
  await printStatus().catch(console.error);
}

export { getStatus, printStatus };
