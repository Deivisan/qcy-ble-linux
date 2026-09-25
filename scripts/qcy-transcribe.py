#!/usr/bin/env python3
"""Transcreve gravacoes do SCO pra validar intelligibilidade de verdade."""
import subprocess
import sys
import wave
from pathlib import Path

from faster_whisper import WhisperModel

TARGET_RATE = 16000


def to_16k_mono(src, dst):
    subprocess.run(
        ["ffmpeg", "-y", "-v", "quiet", "-i", src,
         "-ac", "1", "-ar", str(TARGET_RATE), "-c:a", "pcm_s16le", dst],
        check=True,
    )


def load16k(path):
    with wave.open(path, "rb") as w:
        assert w.getframerate() == TARGET_RATE, w.getframerate()
        assert w.getnchannels() == 1
        assert w.getsampwidth() == 2
        return w.readframes(w.getnframes())


def main(paths, model_size="small", lang="pt"):
    model = WhisperModel(model_size, device="cpu", compute_type="int8")
    for p in paths:
        src = Path(p)
        if not src.exists():
            print(f"\n### {p}: NAO EXISTE")
            continue
        conv = src.with_name(src.stem + "-16k.wav")
        to_16k_mono(str(src), str(conv))
        with wave.open(str(conv), "rb") as w:
            dur = w.getnframes() / w.getframerate()
        segs, info = model.transcribe(
            str(conv), language=lang, beam_size=5,
            vad_filter=False, condition_on_previous_text=False,
        )
        segs = list(segs)
        text = " ".join(s.text.strip() for s in segs).strip()
        print(f"\n### {p}  ({dur:.1f}s)")
        print(f"    idioma detectado: {info.language} p={info.language_probability:.2f}")
        if not segs:
            print("    TRANSCRICAO: <vazio — nenhuma fala reconhecida>")
            continue
        for s in segs:
            print(f"    [{s.start:6.2f} -> {s.end:6.2f}] {s.text.strip()}")
        print(f"    TRANSCRICAO: {text}")


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    size = "small"
    for a in sys.argv[1:]:
        if a.startswith("--model="):
            size = a.split("=", 1)[1]
    main(args, model_size=size)
