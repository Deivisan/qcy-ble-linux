# Checklist pós-reboot — QCY H3S mic

O mic depende de um `btusb` **patcheado e fora da árvore do kernel**. Ele
sobrevive ao reboot por ser DKMS, mas qualquer troca de kernel/distro, ou um
`modprobe -r btusb` acidental, faz o mic voltar a ficar mudo **sem erro
visível**. Rode isto antes de acreditar em qualquer teste.

Última versão: **`0.8-barrot6`**. Estado validado em 28/09/2026.

---

## 1. Verificar o módulo (30 s, sem sudo)

```bash
cat /sys/module/btusb/version
# ESPERADO: 0.8-barrot6
# Se aparecer 0.8 sem sufixo -> o patch NAO esta em uso. O mic vai ficar
# mudo. Ir para o passo 2.

cat /sys/module/btusb/parameters/force_scofix   # ESPERADO: N
cat /sys/module/btusb/parameters/disable_scofix  # ESPERADO: N

modinfo -n btusb
# ESPERADO: .../updates/dkms/btusb.ko   (NUNCA /usr/lib/modules/.../btusb.ko)
```

> `force_scofix=1` **quebra** o mic. O código do kernel sobrescreve
> `sco_mtu` de 255 → 64 sem checar se o valor é válido. Não religue.
> Detalhes em `config/kernel/btusb-barrot-qcy.conf`.

## 2. Se o módulo não for o barrot6 (precisa sudo)

```bash
sudo ./scripts/apply-btusb-esco-count-fix.sh
```

Reinstala a partir do fonte do kernel, aplica P2+P3+P4, compila via DKMS,
instala em `updates/dkms/` e recarrega. Leva ~1 min.

## 3. Conectar o fone e verificar o perfil

```bash
bluetoothctl info 84:AC:60:05:55:2C | grep Connected   # Connected: yes
bluetoothctl connect 84:AC:60:05:55:2C
pactl list cards | grep -A2 bluez_card.84             # Active Profile: a2dp-sink
```

A2DP em repouso é o correto. O HFP entra sozinho quando algo abre o mic.

## 4. O log de 1 linha que decide tudo

```bash
journalctl -k -b | grep "SCO altsetting"
```

**Só aparece quando há sessão de mic ativa.** Exemplo do estado correto:

```
Bluetooth: hci0: SCO altsetting: 3 (air_mode=4 sco_num=1
           voice_setting=0x0000 flag=1 sco_mtu=255)
```

| Campo | Correto | Se estiver diferente |
|-------|---------|----------------------|
| `altsetting` | **3** | 1 ou 2 = P3 não aplicada → mic mudo |
| `air_mode` | 4 | outro = não é CVSD |
| `flag` | 1 | 0 = P3 não está ativa |
| `sco_mtu` | 255 | 64 = `force_scofix=1` ligado |

**Nenhum log = nenhuma sessão SCO = ninguém abriu o mic ainda.** Não conclua
que está quebrado; abra o gravador ou o Whispr Flow primeiro e olhe de novo.

## 5. Teste acústico diferencial (o que realmente prova)

Não serve medir `absmax`/`rms` — já gerou PASS e FAIL falsos. O teste válido
é differential: um tom conhecido sai pelo alto-falante do notebook e é
gravado pelo mic do fone; a energia na frequência do tom tem que aparecer.

```bash
python3 -c "
import wave, struct, math
f=44100; t=[int(12000*math.sin(2*math.pi*1500*n/f)) for n in range(int(f*1.5))]
w=wave.open('/tmp/t1500.wav','wb'); w.setnchannels(1); w.setsampwidth(2)
w.setframerate(f); w.writeframes(struct.pack('<%dh'%len(t), *t)); w.close()
print('tom pronto')"

systemctl --user restart pipewire pipewire-pulse wireplumber
timeout 12 pw-record --target bluez_input.84_AC_60_05_55:2C /tmp/t.wav &
sleep 3
pw-play --target=alsa_output.pci-0000_0a_00.6.analog-stereo /tmp/t1500.wav
wait

python3 -c "
import wave, struct, math
w=wave.open('/tmp/t.wav'); fr=w.getframerate(); raw=w.readframes(w.getnframes())
b=struct.unpack('<%dh'%(len(raw)//2), raw)[3*fr:]
if not b: print('MUDO (stream morreu)'); raise SystemExit
k=2*math.cos(2*math.pi*1500/fr); a=c=0.0
for x in b:
    v=x+k*a-c; c=a; a=v
e=math.sqrt(a*a+c*c-k*a*c)/len(b)
z=100*sum(1 for x in b if x==0)/len(b)
print(f'energia1500={e:.3f} zeros={z:.0f}% -> ' + ('CAPTOU' if e>0.3 else 'MUDO'))"
```

Referência medida em 28/09 (estado bom): **energia 14 a 35, 37% zeros**.
Ruído de fundo com o fone mudo dá ~0.005 a 0.02 e 88% de zeros exatos.

## 6. Validação final: transcrição

O teste acústico prova que o sinal passa. A transcrição prova que é inteligível:

```bash
./scripts/qcy-mic-transcribe.sh
```

Obrigatório falar **durante** a gravação. Sem voz o resultado é vazio e não
significa nada — foi o que gerou um FAIL falso (item 22 da
`TENTATIVAS-SEM-SUCESSO.md`).

## 7. Se o mic estiver mudo apesar de tudo

Verifique, **nesta ordem**:

1. `journalctl -k -b | grep "SCO altsetting"` — qual alt foi escolhido?
2. `journalctl --user -b | grep -i "bluez5\|transport"` — o transporte está
   em `error`? Se sim, é o `pipewire#5467` (contador de erro que nunca zera):
   ```bash
   systemctl --user restart pipewire pipewire-pulse wireplumber
   ```
3. O btusb foi recarregado no meio de uma sessão? O transporte SCO fica
   wedged. Reiniciar os três serviços acima resolve.
4. Só então suspeitar do driver: `dmesg` **retorna vazio neste sistema**, use sempre
   `journalctl -k`.

## O que NÃO fazer

- **Não ligar `force_scofix=1`.** Quebra o mic (o kernel sobrescreve
  `sco_mtu` de 255 para 64).
- **Não ligar `bluez5.enable-msbc`.** O codec negocia, mas o alt 5 (49 bytes)
  não comporta o pacote mSBC de 72 bytes. Codec fecha, áudio chega mudo.
- **Não ignorar o `corrupted SCO packet`.** Depois de corrigido o alt para 3,
  ele ainda aparece a ~354/s e é **contador cosmético** (frames isocônicos
  ociosos de tamanho zero: 600 frames/s × 60% ocioso). O áudio passa limpo.
  **Não tente zerar esse número** — gastei horas nisso.
- **Não criar daemon/keepalive** para segurar o perfil. Já prendeu o perfil
  em HFP por dias (item 23) e o WirePlumber nativo já faz a troca.
- **Não confiar em `dmesg | grep -c`** para contar erros. Retorna vazio e dá
  0 falso (item 28).
- **Não confiar em `grep -c` do log do btmon** para contar eventos. O btmon
  trunca conforme a largura do terminal e já fabricou um "45% de falha"
  inexistente (item 20).
