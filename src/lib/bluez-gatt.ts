/**
 * BlueZ GATT Wrapper via D-Bus
 * Comunicação direta com BlueZ usando dbus-next
 */

import { DBus, DBusError } from 'dbus-next';

export interface BlueZDevice {
  address: string;
  objectPath: string;
  connected: boolean;
}

export class BlueZGatt {
  private bus: DBus;
  private devicePath: string;
  private serviceUUID = '00001001-0000-1000-8000-00805f9b34fb';
  private writeCharUUID = '00001001-0000-1000-8000-00805f9b34fb';
  private notifyCharUUID = '00001002-0000-1000-8000-00805f9b34fb';

  constructor() {
    this.bus = new DBus({
      // Conectar ao system bus (BlueZ roda no system)
      bus: 'system',
    });
    this.devicePath = '';
  }

  async connect(): Promise<void> {
    await this.bus.connect();
    console.log('D-Bus connected');
  }

  async disconnect(): Promise<void> {
    await this.bus.close();
  }

  /**
   * Conecta ao dispositivo Bluetooth pelo MAC address
   */
  async connectDevice(mac: string): Promise<void> {
    // Converter MAC para path D-Bus
    const macEscaped = mac.replace(/:/g, '_');
    this.devicePath = `/org/bluez/hci0/dev_${macEscaped}`;

    try {
      const device = await this.getDeviceInterface();

      // Verificar se já conectado
      const props = await device.Get('org.freedesktop.DBus.Properties');
      const connected = props['Connected'] as boolean;

      if (!connected) {
        console.log(`Conectando a ${mac} via D-Bus...`);
        await device.Connect();
        // Esperar conexão estabelecer
        await this.waitForConnection();
      } else {
        console.log(`Dispositivo ${mac} já conectado`);
      }
    } catch (err) {
      throw new Error(`Falha ao conectar: ${err instanceof Error ? err.message : err}`);
    }
  }

  async disconnectDevice(): Promise<void> {
    if (!this.devicePath) throw new Error('Nenhum dispositivo conectado');
    const device = await this.getDeviceInterface();
    await device.Disconnect();
  }

  /**
   * Envia comando para characteristic principal (0x00001001)
   * Usa WriteValue sem resposta (ideal para throughput)
   */
  async writeCommand(data: Uint8Array): Promise<void> {
    if (!this.devicePath) throw new Error('Dispositivo não conectado');

    const char = await this.getCharacteristic(this.writeCharUUID);
    await char.WriteValue(data, {});
  }

  /**
   * Habilita notificações na characteristic 0x00001002
   * Retorna um stream de eventos
   */
  async readCharacteristic(uuid: string): Promise<Uint8Array> {
    const char = await this.getCharacteristic(uuid);
    const value = await char.ReadValue({});
    return new Uint8Array(Buffer.from(value as Buffer));
  }

  async writeCharacteristic(uuid: string, data: Uint8Array): Promise<void> {
    const char = await this.getCharacteristic(uuid);
    await char.WriteValue(Buffer.from(data), {});
  }

  async enableNotifications(uuid?: string): Promise<AsyncIterable<Uint8Array>> {
    // Se uuid fornecido, usa ele. Senão usa padrão 00001002
    const targetUuid = uuid || this.notifyCharUUID;
    const char = await this.getCharacteristic(targetUuid);

    // Configurar CCCD para notificações (0x0001)
    await this.writeCccdForCharacteristic(char);

    // Iniciar notificações
    await char.StartNotify();

    return this.listenToNotifications(targetUuid);
  }

  async disableNotifications(uuid?: string): Promise<void> {
    const targetUuid = uuid || this.notifyCharUUID;
    const char = await this.getCharacteristic(targetUuid);
    await char.StopNotify();
  }

  // ----------------- privados -----------------

  private async writeCccdForCharacteristic(char: any): Promise<void> {
    // Obter path do descriptor CCCD (0x2902) para esta characteristic
    const charPath = char.path; // D-Bus object path
    const cccdPath = charPath + '/desc00002902-0000-1000-8000-00805f9b34fb';

    try {
      const iface = {
        type: 'org.bluez.GattDescriptor1',
        methods: ['WriteValue'],
      };
      const desc = await this.bus.getProxyObject('org.bluez', cccdPath, [iface]);
      const buf = Buffer.alloc(2);
      buf.writeUInt16LE(0x0001, 0); // 0x0001 = notifications enable
      await desc.WriteValue(Buffer.from(buf), {});
    } catch (err) {
      // CCCD pode não existir ou caminho diferente => ignorar
      console.warn('CCCD write failed (notif pode não funcionar):', err);
    }
  }

  async disableNotifications(): Promise<void> {
    if (!this.devicePath) throw new Error('Dispositivo não conectado');

    const char = await this.getCharacteristic(this.notifyCharUUID);
    await char.StopNotify();
  }

  /**
   * Lê versão do firmware (characteristic 0x00000007)
   */
  async readVersion(): Promise<string> {
    const char = await this.getCharacteristic('00000007-0000-1000-8000-00805f9b34fb');
    const value = await char.ReadValue({});
    const bytes = new Uint8Array(value as Buffer);
    // formato: 3 bytes (major, minor, patch) ou 6 bytes separados
    if (bytes.length === 6) {
      return `${bytes[0]}.${bytes[1]}.${bytes[2]} (L) / ${bytes[3]}.${bytes[4]}.${bytes[5]} (R)`;
    }
    return `${bytes[0]}.${bytes[1]}.${bytes[2]}`;
  }

  /**
   * Lê bateria (characteristic 0x00000008)
   */
  async readBattery(): Promise<{left: number; right: number; case?: number}> {
    const char = await this.getCharacteristic('00000008-0000-1000-8000-00805f9b34fb');
    const value = await char.ReadValue({});
    const bytes = new Uint8Array(value as Buffer);

    const decode = (b: number) => {
      const charging = !!(b & 0x80);
      const level = b & 0x7F;
      return { level, charging };
    };

    if (bytes.length >= 3) {
      const left = decode(bytes[0]);
      const right = decode(bytes[1]);
      const cas = bytes[2] !== undefined ? decode(bytes[2]) : null;
      return {
        left: left.level,
        right: right.level,
        case: cas?.level,
      };
    }
    throw new Error('Battery unexpected data length');
  }

  // ----------------- privados -----------------

  private async getDeviceInterface() {
    const iface = 'org.bluez.Device1';
    return await this.bus.getProxyObject('org.bluez', this.devicePath, [
      { type: 's', name: iface },
    ]);
  }

  private async getService(uuid: string) {
    // Obter objeto do service via introspection do device
    const { services } = await this.introspectObject(this.devicePath) as any;
    const service = services.find((s: any) => s.uuid === uuid);
    if (!service) throw new Error(`Service ${uuid} não encontrado`);
    return {
      path: service.path,
      uuid: service.uuid,
    };
  }

  private async getCharacteristic(uuid: string): Promise<any> {
    // Construir path manual: service00001001 (QCY main) e char com último 4 dígitos do UUID
    const uuidDigits = uuid.replace(/-/g, '');
    const charName = `char${uuidDigits.slice(-8)}`; // exemplo: char00001002
    const servicePath = `${this.devicePath}/service00001001`;
    const charPath = `${servicePath}/${charName}`;

    const iface = {
      type: 'org.bluez.GattCharacteristic1',
      methods: ['ReadValue', 'WriteValue', 'StartNotify', 'StopNotify'],
      signals: ['PropertiesChanged'],
    };

    try {
      return await this.bus.getProxyObject('org.bluez', charPath, [iface]);
    } catch (err) {
      throw new Error(`Characteristic ${uuid} não encontrada em ${charPath}: ${err}`);
    }
  }

  private async writeCccd(path: string, value: number): Promise<void> {
    // CCCD é descriptor 0x2902. Escrever como array de 2 bytes LE
    const cccdPath = path + '/desc00002902-0000-1000-8000-00805f9b34fb';
    const iface = {
      type: 'org.bluez.GattDescriptor1',
      methods: ['WriteValue'],
    };
    try {
      const desc = await this.bus.getProxyObject('org.bluez', cccdPath, [iface]);
      const buf = Buffer.alloc(2);
      buf.writeUInt16LE(value, 0);
      await desc.WriteValue(Buffer.from(buf), {});
    } catch (err) {
      // CCCD pode não existir, ignorar
      console.warn('CCCD write failed (pode não existir):', err);
    }
  }

  private async listenToNotifications(): AsyncIterable<Uint8Array> {
    // Criar listener para o signal PropertiesChanged na characteristic
    // BlueZ envia notificações via signal "PropertiesChanged" com interface "org.freedesktop.DBus.Properties"
    // Mas a characteristic também emite signal "CharacteristicValue" via GattCharacteristic1

    // Vamos usar um EventEmitter简单 (mas como não temos eventos, retorno um iterador que lê via chamada polling? Não, D-Bus signals são async)

    // Para simplicidade, retorno um async generator que escuta o bus.match
    const match = {
      type: 'signal',
      sender: 'org.bluez',
      path: this.devicePath + '/service00001001/char00001002',
    };

    const stream = this.bus.addMatch(match);

    // Nota: O BlueZ envia notificações como signal 'PropertiesChanged' com property 'Value' (array of bytes)
    // Vamos ler do stream

    return {
      [Symbol.asyncIterator]: async function* () {
        for await (const msg of stream) {
          // msg é mensagem D-Bus
          const body = msg.body as any;
          if (body && body.Value && typeof body.Value === 'object' && 'value' in body.Value) {
            yield new Uint8Array(Buffer.from(body.Value.value));
          }
        }
      },
    };
  }

  private async waitForConnection(): Promise<void> {
    // Polling simples até Connected=true no Device1
    for (let i = 0; i < 20; i++) {
      const device = await this.getDeviceInterface();
      const props = await device.Get('org.freedesktop.DBus.Properties');
      if (props['Connected']) {
        console.log('Conectado!');
        return;
      }
      await new Promise((r) => setTimeout(r, 500));
    }
    throw new Error('Timeout aguardando conexão');
  }

  private async introspectObject(path: string): Promise<any> {
    const iface = 'org.freedesktop.DBus.Introspectable';
    const obj = await this.bus.getProxyObject('org.bluez', path, [{ type: iface }]);
    const introspector = obj.getInterface(iface);
    const xml = await introspector.Introspect();
    return this.parseIntrospection(xml, path);
  }

  private parseIntrospection(xml: string, basePath: string): any {
    // Parser simples de XML introspection do D-Bus
    const services: any[] = [];
    const regex = /<node name="([^"]+)">([\s\S]*?)<\/node>/g;
    let match;

    while ((match = regex.exec(xml)) !== null) {
      const name = match[1];
      const content = match[2];
      const path = basePath + (basePath.endsWith('/') ? '' : '/') + name;
      const serviceMatch = content.match(
        /<interface name="org\.bluez\.GattService1">[\s\S]*?uuid">([^<]+)<\/property>/
      );
      const charMatch = content.match(
        /<interface name="org\.bluez\.GattCharacteristic1">[\s\S]*?uuid">([^<]+)<\/property>/
      );

      if (serviceMatch) {
        services.push({ path, uuid: serviceMatch[1].trim() });
      } else if (charMatch) {
        // Característica será tratada como filha do service
        // Aqui simplificamos: retorna array de characteristics por service posteriormente
      }
    }

    return { services };
  }
}

// -------------------- Fábrica --------------------

export function createBlueZClient(): BlueZGatt {
  return new BlueZGatt();
}
