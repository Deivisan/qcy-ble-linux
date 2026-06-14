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
  const qcyBlock = output
    .split(/\n(?=Card #)/)
    .find(block => block.includes('Name: bluez_card.84_AC_60_05_55_2C')) || '';

  // detecta perfil ativo
  const profileMatch = qcyBlock.match(/Active Profile:\s*(.+)/);
  if (profileMatch) {
    status.profile = profileMatch[1].trim();
  }

  // detecta nome do card
  const cardMatch = qcyBlock.match(/Name:\s+(bluez_card\.[\d_AC:]+)/);
  if (cardMatch) {
    status.bluetooth_card = cardMatch[1];
  }

  return status;
}

async function detectUsbQcy(): Promise<{ card: string | null; source: string | null }> {
  try {
    const { stdout } = await execAsync('pactl list cards short');
    const line = stdout.split('\n').find(l => /3654:4a55|jieli.*qcy|qcy h3s/i.test(l));
    if (line) {
      const card = line.split('\t')[1];
      const usbSource = 'alsa_input.usb-Jieli_Technology_QCY_H3S_433132373431352E-00.mono-fallback';
      return { card, source: usbSource };
    }
    return { card: null, source: null };
  } catch {
    return { card: null, source: null };
  }
}

async function detectHeavyAgents(): Promise<string[]> {
  try {
    const { stdout } = await execAsync('ps aux');
    const agents: string[] = [];
    const patterns = ['browseros', 'soda', 'open-whispr', 'whisper', 'SpeechRecognitionService'];
    for (const p of patterns) {
      if (new RegExp(p, 'i').test(stdout)) agents.push(p);
    }
    return agents;
  } catch {
    return [];
  }
}

async function getStatus(): Promise<DeviceStatus & { usbQcy?: any; heavyAgents?: string[] }> {
  const [pactlOutput, btInfo, pwStatus] = await Promise.all([
    getPactlInfo(),
    checkBluetoothctl(),
    getPipeWireStatus(),
  ]);

  const parsed = parseCardInfo(pactlOutput);
  const usb = await detectUsbQcy();
  const heavy = await detectHeavyAgents();

  const macFromCard = parsed.bluetooth_card?.replace('bluez_card.', '').replace(/_/g, ':') || null;
  const cardSuffix = parsed.bluetooth_card?.replace('bluez_card.', '') || null;

  return {
    connected: btInfo !== null,
    profile: parsed.profile,
    source: macFromCard ? `bluez_input.${macFromCard}` : null,
    sink: cardSuffix ? `bluez_output.${cardSuffix}` : null,
    bluetooth_card: parsed.bluetooth_card,
    usbQcy: usb.card ? { card: usb.card, source: usb.source } : null,
    heavyAgents: heavy,
  };
}

async function printStatus(): Promise<void> {
  const status = await getStatus();

  console.log(chalk.bold('\n📊 Status do QCY H3S\n'));

  console.log(`${chalk.green('✔')} Bluetooth: ${status.connected ? chalk.green('conectado') : chalk.red('desconectado')}`);

  if (status.bluetooth_card) {
    console.log(`${chalk.cyan('ℹ')} Card BT: ${status.bluetooth_card}`);
  }

  if (status.profile) {
    const color = status.profile.includes('headset') ? chalk.yellow : chalk.cyan;
    console.log(`${color('▸')} Perfil BT ativo: ${color(status.profile)}`);
  } else {
    console.log(`${chalk.yellow('⚠')} Perfil BT: ${chalk.yellow('não detectado')}`);
  }

  if (status.source) {
    console.log(`${chalk.magenta('🔊')} Source BT: ${status.source}`);
  }

  if (status.sink) {
    console.log(`${chalk.blue('🔈')} Sink BT: ${status.sink}`);
  }

  // Heavy agents warning (proteção contra freeze no BT)
  if (status.heavyAgents && status.heavyAgents.length > 0) {
    console.log(chalk.red('\n🚨 AGENTES PESADOS DETECTADOS (browseros/soda/open-whispr etc):'));
    console.log(`   ${status.heavyAgents.join(', ')}`);
    console.log(chalk.red('   NÃO use "profile hfp" nem rode qcy-mic-recover.sh enquanto estes estiverem rodando.'));
    console.log(chalk.yellow('   Rode: ./scripts/transcription-safe.sh antes de transcrever (mata os agentes).'));
  }

  // sugestão de comando para test do mic (só bluetooth side)
  if (status.profile?.includes('headset')) {
    console.log(chalk.green('\n💡 Teste rápido do microfone BT:'));
    console.log(`   timeout 5 pw-record --target ${status.source} /tmp/qcy-test.wav`);
  } else if (status.bluetooth_card) {
    console.log(chalk.yellow('\n💡 Para ativar microfone via Bluetooth (só se NÃO tiver agentes pesados rodando):'));
    console.log('   bun run src/cli/profile.ts hfp --force');
    console.log(chalk.red('   ⚠️ Risco alto de freeze se BrowserOS/open-whispr/whisper estiver ativo.'));
  }

  // Nota sobre o cabo: ele sempre funcionou estável, não é gerenciado por estes comandos.
  console.log(chalk.gray('\n(nota: o cabo USB do QCY sempre foi estável e não é alterado por profile/recover)'));
  console.log('');
}

if (import.meta.main) {
  await printStatus().catch(console.error);
}

export { getStatus, printStatus };
