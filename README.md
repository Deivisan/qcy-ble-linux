# qcy-control 🎧

sistema robusto de controle para fones **QCY H3S/H2S** no linux, com cli, daemon e interface gráfica.

## 🎯 missão

fornecer controle completo sobre:

- ✅ perfis de áudio (a2dp ↔ hfp/hsp)
- ✅ eventos dos botões (avrcp/mpris)
- ✅ automações customizadas
- ✅ monitoramento de status em tempo real

## 🚀 quick start

```bash
# instalar dependências
bun install

# testar captura de eventos (requer permissões sudo)
bun run evtest /dev/input/event19

# verificar status do dispositivo
bun run start status

# iniciar daemon de automações
bun run daemon
```

## 📂 estrutura do projeto

```
src/
├── cli/
│   ├── evtest.ts    # mapeamento de botões via evdev
│   └── status.ts    # consulta a pipewire/bluez
├── daemon/           # serviço de background para automações
├── gui/              # interface web-based (electron/static)
├── lib/
│   └── config.ts    # configurações e constantes
└── index.ts          # ponto de entrada principal
```

## 🧪 status atual do desenvolvimento

- [x] estrutura bun + typescript
- [x] comando cli: `evtest` (captura mock de eventos)
- [x] comando cli: `status` (consulta pipewire/bluez)
- [x] configuração base em src/lib/config.ts
- [ ] integração real com evdev (/dev/input/event*)
- [ ] daemon para automações de botões
- [ ] configuração persistente (~/.config/qcy/)
- [ ] gui web-based
- [ ] empacotamento (appimage/flatpak)

## 🔧 stack técnica

- **runtime:** bun 1.3.x
- **linguagem:** typescript 5.x
- **áudio:** pipewire 1.6.x + wireplumber 0.5.x
- **bluetooth:** bluez 5.86+
- **eventos:** evdev (linux input subsystem)
- **controle de mídia:** mpris2 via dbus
- **gui futura:** tauri/electron (a decidir)

## 📋 próximas etapas (roadmap)

### fase 1: CLI funcional (atual)
1. implementar leitura real de eventos evdev
2. mapear todos os botões do qcy h3s
3. permitir salvar mapeamento personalizado
4. adicionar comando para alternar perfil

### fase 2: daemon
1. escutar eventos em background
2. executar ações customizadas por botão
3. suporte a scripts shell
4. daemon systemd user

### fase 3: GUI
1. painel web local (port 3000)
2. configurar botões via interface
3. ver status em tempo real
4. perfis pré-configurados

## 📚 referências

- [diagnóstico completo do qcy h3s](qcy-fix.md)
- [pipewire - sound configuration](https://wiki.archlinux.org/title/pipewire)
- [bluez - bluetooth configuration](https://wiki.archlinux.org/title/bluetooth)
- [evdev - linux input events](https://www.kernel.org/doc/html/latest/input/evdev.html)

## 🧾 contexto atual do host

- o fone QCY H3S está **conectado via bluetooth** e deve permanecer assim enquanto você estiver usando
- o dispositivo aparece com UUIDs de:
  - `Audio Sink`
  - `A/V Remote Control Target`
  - `A/V Remote Control`
  - `Handsfree`
- o sistema expõe o headset como `QCY H3S (AVRCP)` em `event19`
- o PipeWire/WirePlumber já vê o fone como dispositivo bluez e como sink de áudio ativo
- o próximo passo seguro é **observar e mapear**, não reconectar nem desconectar

## 🔭 próximos passos sugeridos

1. mapear quais códigos chegam em `event19` quando você aperta os botões do fone
2. separar ações simples de ações compostas por clique duplo/triplo
3. decidir a camada de automação:
	- `MPRIS` para mídia
	- `evdev` para eventos crus
	- `daemon` para regras customizadas
4. começar a desenhar a GUI pensando em:
	- perfis
	- botões
	- ações
	- prioridade de comportamento
