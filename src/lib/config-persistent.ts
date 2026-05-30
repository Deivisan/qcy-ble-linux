/**
 * QCY Control - Gerenciador de Configuração Persistente
 * Usa a biblioteca 'conf' para armazenar configurações do usuário
 */

import { Conf } from 'conf';
import { join } from 'path';
import { homedir } from 'os';

export interface QCYConfig {
  device: {
    mac: string;
    evdevPath: string;
  };
  profiles: {
    default: 'a2dp' | 'hfp';
    autoSwitch: boolean;
  };
  actions: {
    playPause: string;
    nextTrack: string;
    prevTrack: string;
    volumeUp: string;
    volumeDown: string;
  };
  daemon: {
    enabled: boolean;
    debug: boolean;
  };
}

const DEFAULT_CONFIG: QCYConfig = {
  device: {
    mac: '84:AC:60:05:55:2C',
    evdevPath: '/dev/input/event19',
  },
  profiles: {
    default: 'a2dp',
    autoSwitch: true,
  },
  actions: {
    playPause: 'mpris:playpause',
    nextTrack: 'mpris:next',
    prevTrack: 'mpris:previous',
    volumeUp: 'command:pactl set-sink-volume @DEFAULT_SINK@ +5%',
    volumeDown: 'command:pactl set-sink-volume @DEFAULT_SINK@ -5%',
  },
  daemon: {
    enabled: true,
    debug: false,
  },
};

const config = new Conf<QCYConfig>({
  projectName: 'qcy-control',
  defaults: DEFAULT_CONFIG,
  schema: {
    device: {
      mac: {
        type: 'string',
      },
      evdevPath: {
        type: 'string',
      },
    },
    profiles: {
      default: {
        type: 'string',
        enum: ['a2dp', 'hfp'],
      },
      autoSwitch: {
        type: 'boolean',
      },
    },
    actions: {
      playPause: { type: 'string' },
      nextTrack: { type: 'string' },
      prevTrack: { type: 'string' },
      volumeUp: { type: 'string' },
      volumeDown: { type: 'string' },
    },
    daemon: {
      enabled: { type: 'boolean' },
      debug: { type: 'boolean' },
    },
  },
});

// helpers
export function getConfig(): QCYConfig {
  return config.store;
}

export function updateConfig(partial: Partial<QCYConfig>): void {
  config.set(partial);
}

export function resetConfig(): void {
  config.clear();
}

export function getConfigPath(): string {
  return config.path;
}
