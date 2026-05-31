/**
 * Protocolo QCY BLE - Implementação baseada no projeto Quicky
 * Documentação: https://github.com/hui1601/Quicky
 */

export enum QCYCommand {
  ResetDefault = 0x01,
  ClearPairing = 0x02,
  FactoryReset = 0x03,
  MusicControl = 0x04,
  LightFlash = 0x05,
  InEarDetection = 0x06,
  NoiseValue = 0x07,
  Volume = 0x08,
  LowLatency = 0x09,
  Monitoring = 0x0A,
  NoiseCancelMode = 0x0C,
  TestMode = 0x0D,
  SleepMode = 0x10,
  EarTipFitTest = 0x11,
  LedMode = 0x12,
  PowerManager = 0x14,
  SoundBalance = 0x16,
  ANCSetting = 0x17,
  RenameDevice = 0x18,
  VoiceLanguage = 0x19,
  ToneVolume = 0x1D,
  TakePhoto = 0x1E,
  Standby = 0x1F,
  EQParamsV1 = 0x20,
  EQParamsV2 = 0x22,
  LDAC = 0x23,
  AdaptiveEQ = 0x27,
  ANCResult = 0x28,
  ANCwear = 0x29,
  KeyFunction = 0x2B,
  WearingDetection = 0x2C,
  SpatialAudio = 0x2D,
  MusicMode = 0x2E,
  Battery = 0x2F,
  Version = 0x30,
  EnvAdaptation = 0x32,
  TWSEnable = 0x34,
  LEDSwitch = 0x35,
  LEDEffect = 0x36,
  PlayMode = 0x37,
  FocusMode = 0x39,
  MusicStatus = 0x3A,
  MusicInfo = 0x3B,
  TonePlay = 0x3D,
  SyncTime = 0x3E,
  Alarm = 0x3F,
  AI = 0x43,
  MaxEQCount = 0x44,
  CustomEQTest = 0x45,
  EQLeft = 0x46,
  EQRight = 0x47,
  InEarSensitivity = 0x48,
  GameConfig = 0x4A,
  RequestData = 0xFE,
}

export enum ANCSettingMode {
  OFF = 0x00,
  ANC = 0x02,
  OUTDOOR = 0x03,
  TRANSPARENCY = 0x04,
  // Transparency levels (sub-scene 1-7)
  TRANSPARENCY_L1 = 0x0A,
  TRANSPARENCY_L2 = 0x0B,
  TRANSPARENCY_L3 = 0x0C,
  TRANSPARENCY_L4 = 0x0D,
  TRANSPARENCY_L5 = 0x0E,
  TRANSPARENCY_L6 = 0x0F,
  TRANSPARENCY_L7 = 0x10,
}

export enum NoiseCancelSimpleMode {
  OFF = 0x00,
  ANC = 0x01,
  OUTDOOR = 0x02,
  TRANSPARENCY = 0x03,
}

export enum LowLatencyMode {
  DISABLE = 0x02,
  ENABLE = 0x01,
}

export enum MusicControl {
  PLAY = 0x01,
  PAUSE = 0x02,
  PREV = 0x03,
  NEXT = 0x04,
}

export class QCYProtocol {
  /**
   * Constrói pacote de comando com framing 0xFF
   */
  static buildPacket(cmd: QCYCommand, params: number[] = []): Uint8Array {
    const bodyLen = 1 + params.length; // cmd + params
    const packet = new Uint8Array(2 + bodyLen);
    packet[0] = 0xFF;
    packet[1] = bodyLen;
    packet[2] = cmd;
    for (let i = 0; i < params.length; i++) {
      packet[3 + i] = params[i];
    }
    return packet;
  }

  /**
   * Parse de notificação (mesmo framing)
   */
  static parseNotification(data: Uint8Array): { cmd: QCYCommand; params: Uint8Array } | null {
    if (data[0] !== 0xFF) return null;
    const bodyLen = data[1];
    if (data.length < 2 + bodyLen) return null;

    const cmd = data[2];
    const params = data.slice(3, 3 + bodyLen - 1);
    return { cmd, params };
  }

  /**
   * Pacote para comando 0x0C (Noise Cancel Mode simples)
   */
  static noiseCancelSimple(mode: NoiseCancelSimpleMode): Uint8Array {
    return this.buildPacket(QCYCommand.NoiseCancelMode, [mode]);
  }

  /**
   * Pacote para comando 0x17 (ANC Setting avançado)
   */
  static ancSetting(mode: number, subScene: number, noiseValue: number): Uint8Array {
    return this.buildPacket(QCYCommand.ANCSetting, [mode, subScene, noiseValue]);
  }

  /**
   * Pacote para Volume (0x08)
   */
  static volume(left: number, right: number): Uint8Array {
    return this.buildPacket(QCYCommand.Volume, [left, right, 0x00]);
  }

  /**
   * Pacote para Low Latency (0x09)
   */
  static lowLatency(enabled: boolean): Uint8Array {
    return this.buildPacket(QCYCommand.LowLatency, [enabled ? LowLatencyMode.ENABLE : LowLatencyMode.DISABLE]);
  }

  /**
   * Pacote para Request Data (0xFE) — lê valor atual de qualquer cmd
   */
  static requestData(cmd: QCYCommand): Uint8Array {
    return this.buildPacket(QCYCommand.RequestData, [cmd]);
  }

  /**
   * Pacote para Music Control (0x04)
   */
  static musicControl(action: MusicControl): Uint8Array {
    return this.buildPacket(QCYCommand.MusicControl, [action]);
  }

  /**
   * Pacote para In-Ear Detection (0x06)
   */
  static inEarDetection(enable: boolean): Uint8Array {
    return this.buildPacket(QCYCommand.InEarDetection, [enable ? 0x01 : 0x02]);
  }

  // TODO: outros comandos conforme necessidade
}

// Helper para decode de battery
export function decodeBattery(bytes: Uint8Array): { level: number; charging: boolean }[] {
  return Array.from(bytes).map((b) => ({
    level: b & 0x7F,
    charging: !!(b & 0x80),
  }));
}

// Helper para decode de version
export function decodeVersion(bytes: Uint8Array): string {
  if (bytes.length === 6) {
    return `${bytes[0]}.${bytes[1]}.${bytes[2]} (L) / ${bytes[3]}.${bytes[4]}.${bytes[5]} (R)`;
  }
  if (bytes.length >= 3) {
    return `${bytes[0]}.${bytes[1]}.${bytes[2]}`;
  }
  return 'unknown';
}
