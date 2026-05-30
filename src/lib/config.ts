{
  "version": "1.0.0",
  "last_updated": "2026-05-29",
  "device": {
    "name": "QCY H3S",
    "vendor_id": "3654",
    "product_id": "4a55",
    "bluetooth_mac": "84:AC:60:05:55:2C"
  },
  "avrcp_events": {
    "164": {
      "name": "play_pause",
      "description": "botão play/pause",
      "action": "mpris_play_pause"
    },
    "166": {
      "name": "next_track",
      "description": "próxima faixa",
      "action": "mpris_next"
    },
    "167": {
      "name": "prev_track",
      "description": "faixa anterior",
      "action": "mpris_previous"
    },
    "168": {
      "name": "volume_up",
      "description": "volume +",
      "action": "volume_up"
    },
    "169": {
      "name": "volume_down",
      "description": "volume -",
      "action": "volume_down"
    }
  },
  "bluez": {
    "card_name": "bluez_card.84_AC_60_05_55_2C",
    "profiles": ["a2dp-sink", "headset-head-unit"],
    "preferred_profile": "headset-head-unit"
  },
  "pipewire": {
    "alsa_source": "alsa_input.usb-Jieli_Technology_QCY_H3S_433132373431352E-00.mono-fallback",
    "alsa_sink": "alsa_output.usb-Jieli_Technology_QCY_H3S_433132373431352E-00.analog-stereo"
  }
}
