#!/usr/bin/env bun

/**
 * QCY Control - Profile Switcher
 * Alterna entre perfis A2DP (áudio) e HFP (headset com mic)
 */

import { exec } from 'child_process';
import { promisify } from 'util';
import chalk from 'chalk';

const execAsync = promisify(exec);

const PROFILE_A2DP = 'a2dp-sink';
const PROFILE_HFP = 'headset-head-unit';

interface ProfileSwitchOptions {
  deviceMac?: string;
  force?: boolean;
}

async function getCardName(mac: string): Promise<string | null> {
  try {
    const { stdout } = await execAsync('pactl list cards short');
    const line = stdout.split('\n').find(l => l.includes(mac.replace(/:/g, '_')));
    if (line) {
      return line.split('\t')[1];
    }
    return null;
  } catch {
    return null;
  }
}

async function getActiveProfile(card: string): Promise<string | null> {
  try {
    const { stdout } = await execAsync(`pactl get-card-profile ${card}`);
    const match = stdout.match(/Active Profile:\s+(.+)/);
    return match ? match[1].trim() : null;
  } catch {
    return null;
  }
}

async function setProfile(card: string, profile: string): Promise<void> {
  await execAsync(`pactl set-card-profile ${card} ${profile}`);
}

async function switchProfile(targetProfile: string, options: ProfileSwitchOptions = {}): Promise<void> {
  const mac = options.deviceMac || '84:AC:60:05:55:2C';
  console.log(chalk.cyan(`🔄 verificando dispositivo ${mac}...`));

  const card = await getCardName(mac);
  if (!card) {
    throw new Error(`card bluetooth não encontrado para ${mac}. '
      'verifique se o dispositivo está conectado.`);
  }

  console.log(chalk.gray(`card: ${card}`));

  const current = await getActiveProfile(card);
  console.log(chalk.yellow(`perfil atual: ${current || 'nenhum'}`));

  if (current === targetProfile && !options.force) {
    console.log(chalk.green('✅ já no perfil desejado.'));
    return;
  }

  console.log(chalk.cyan(`▶️  mudando para ${targetProfile}...`));
  await setProfile(card, targetProfile);

  // aguarda um pouco e valida
  await new Promise(resolve => setTimeout(resolve, 500));
  const newProfile = await getActiveProfile(card);

  if (newProfile === targetProfile) {
    console.log(chalk.green(`✅ perfil alterado para ${targetProfile}`));
  } else {
    console.log(chalk.red(`❌ falha: ainda em ${newProfile}`));
  }
}

// subcomandos
export async function toA2DP(options: ProfileSwitchOptions): Promise<void> {
  await switchProfile(PROFILE_A2DP, options);
}

export async function toHFP(options: ProfileSwitchOptions): Promise<void> {
  await switchProfile(PROFILE_HFP, options);
}

export async function toggle(options: ProfileSwitchOptions = {}): Promise<void> {
  const mac = options.deviceMac || '84:AC:60:05:55:2C';
  const card = await getCardName(mac);
  if (!card) throw new Error('dispositivo não encontrado');

  const current = await getActiveProfile(card);
  const target = current?.includes('headset') ? PROFILE_A2DP : PROFILE_HFP;
  await switchProfile(target, options);
}

if (import.meta.main) {
  const args = process.argv.slice(2);
  const command = args[0];

  const opts = {
    deviceMac: process.env.QCY_DEVICE_MAC || '84:AC:60:05:55:2C',
    force: args.includes('--force') || args.includes('-f'),
  };

  switch (command) {
    case 'a2dp':
      toA2DP(opts).catch(console.error);
      break;
    case 'hfp':
      toHFP(opts).catch(console.error);
      break;
    case 'toggle':
      toggle(opts).catch(console.error);
      break;
    default:
      console.log(`
🔀 Profile Switcher - QCY Control

uso:
  bun run src/cli/profile.ts <comando> [opções]

comandos:
  a2dp      mudar para perfil a2dp (alta qualidade, sem mic)
  hfp       mudar para perfil hfp/hsp (com microfone, qualidade reduzida)
  toggle    alternar entre perfis automaticamente

opções:
  --mac <endereço>   mac address do dispositivo (padrão: 84:AC:60:05:55:2C)
  --force            forçar mudança mesmo se já estiver no perfil

exemplos:
  bun run src/cli/profile.ts a2dp
  bun run src/cli/profile.ts hfp --force
`);
  }
}
