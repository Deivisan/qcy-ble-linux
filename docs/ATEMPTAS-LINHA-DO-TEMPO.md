# Linha do tempo — por que o mic do QCY H3S ficou 3 meses quebrado

Resumo das tentativas em ordem cronológica, com o que cada uma provou e o
que errou. Detalhes técnicos em `docs/KERNEL-BTUSB-BARROT.md`; erros
específicos em `TENTATIVAS-SEM-SUCESSO.md`; checklist pós-reboot em
`POST-REBOOT.md`.

| # | Data | O que foi tentado | Resultado | O que ensinou |
|---|------|-------------------|-----------|----------------|
| 1 | jun/2026 | HFP via `bluez5.enable-msbc=true` | Codec negocia, áudio **mudo** | mSBC é imposible neste dongle: alt 5 = 49 bytes < 72 do pacote. Item 5. |
| 2 | jun/2026 | Perfis manuais, HFP fixo | Áudio, mas travava tudo | Perfil fixo impede o retorno a A2DP. Não é solução. |
| 3 | jun/2026 | `qcy-mic-warm.service` + timer, `pw-record` keepalive | "Funciona" por prender o perfil em HFP | Prendeu o perfil em HFP **por dias**. Item 23. Removido. |
| 4 | jun/2026 | Leitura de `battery` via GATT | Falhou | UUID `00002a06` não responde neste firmware. |
| 5 | jul–ago/2026 | Nenhuma investigação real | Nada | O mic ficou 3 meses sem análise de kernel. |
| 6 | 25/09/2026 | Descoberta do `btusb` stock + `force_scofix=1` | Reduziu `corrupted SCO` | **`force_scofix=1` é a 2ª causa raiz.** Item 27. |
| 7 | 25/09/2026 | P1: "eSCO-aware SCO count" via `hci_conn_num` | **Dano real** | `hci_conn_num(SCO_LINK)` e `hci_conn_num(ESCO_LINK)` são o **mesmo contador**. Premissa falsa. Item 21. |
| 8 | 25/09/2026 | `btmon \| grep -c "corrupted"` | "0 erros" | **Falso.** btmon trunca as linhas pela largura do terminal e fabricou "9/9" e depois "45% de falha". Item 20. |
| 9 | 25/09/2026 | `dmesg \| grep -c "corrupted SCO"` | "0 erros" | **Falso.** `dmesg` retorna **vazio** neste sistema. Real: 1755. Item 28. |
| 10 | 25/09/2026 | RMS/`absmax` para "provar" o mic | PASS **e** FAIL falsos | Sem alguém falando, ou sem tom conhecido, a métrica não diz nada. Item 22. |
| 11 | 25/09/2026 | P2: SCO clássico `0x0028` | Funciona | **Necessário**, confirmado por A/B: com `0x043d` vem **zero pacotes** no ar. Item 31. |
| 12 | 25/09/2026 | P3 v1: tabela `{2,4,5}` do ramo 2EV3 → **alt 2 (17 B)** | Ainda mudo | Precisai de 2 revisões. Item 30. |
| 13 | 26/09/2026 | `btusb_work()` não loga o alt no caminho de sucesso | Bug invisível | P4: log de observabilidade. Sem ele, nenhuma das Above era verificável. |
| 14 | 26/09/2026 | Enum `HCI_NOTIFY_ENABLE_SCO_CVSD` invertido | Conclusão errada | `air_mode=4` é CVSD, não TRANSP. |
| 15 | 27/09/2026 | Reinício do BlueZ / unbind-rebind USB como cura do handle obsoleto | Não cura | Unbind de driver **não** é corte de energia. |
| 16 | 27/09/2026 | Suspeita de `pipewire#5467` (transporte wedged) | Parcialmente confirmado | `systemctl --user restart pipewire pipewire-pulse wireplumber` cura, mas **não era a causa** — era consequência da corrupção. |
| 17 | **28/09/2026** | **`lsusb -v` no EP 3 IN** | **RESOLVEU** | alt 1=9, 2=17, **3=25**, 4=33, 5=49 B. Pacote CVSD = 24 B. Só o alt 3 cabe. |
| 18 | 28/09/2026 | A/B desligando o P2 | P2 é necessário | Mantido. Item 31. |
| 19 | 28/09/2026 | P3 v2: tabela exclusiva do Barrot `{3,4,5}` | **FUNCIONA** | Energia do tom: 0.017 → 14.816 (~870×). 4/4 sessões. |

## A lição que amarra tudo

Quatro tentativas (7, 9, 10, 14) falharam pelo **mesmo motivo**: medi a
intenção do sistema em vez do que acontece no hardware.

- Li o que o driver *escolhia*, não o que o dongle *aceita* → precisou de
  `lsusb -v`.
- Li o que o kernel *logava*, não o que o hardware *mandava* → precisou de
  `btmon` com saida em arquivo.
- Medi *energia* do áudio, não *conteúdo* → precisou de tom conhecido e
  Whisper.
- Confiei em contador de log que não media nada (`dmesg`, `grep` do btmon).

**A regra que teria economizado 3 meses:** antes de propor um patch,_write
`lsusb -v -d <vid>:<pid>`, `btmon > arquivo` e um teste acústico diferencial.
Três comandos, 10 minutos, e nenhum deles mente.
