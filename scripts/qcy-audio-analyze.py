#!/usr/bin/env python3
"""Analise objetiva de captura SCO: ruido de fundo, dropouts, clipping, energia.

Nao decide "passou" so por absmax -- mede coisas que humans ouvem:
  - ruido de floor (seco = nada captado)
  - fracao de frames abaixo do floor (dropouts/pacotes perdidos)
  - janelas de silencio no meio da fala (audio quebrado)
  - clipping
"""
import math
import struct
import sys
import wave


def read_wav_mono(path):
    with wave.open(path, "rb") as w:
        ch = w.getnchannels()
        sw = w.getsampwidth()
        rate = w.getframerate()
        n = w.getnframes()
        raw = w.readframes(n)
    if sw != 2:
        raise SystemExit(f"sampwidth {sw} nao suportado")
    step = ch
    n = len(raw) // 2
    vals = struct.unpack("<" + "h" * n, raw[: n * 2])
    mono = [vals[i] for i in range(0, n, step)]
    return rate, mono


def voice_band_ratio(v, rate):
    """Razao energia_baixa/energia_alta, sem numpy.

    Voz humana concentra energia abaixo de ~2 kHz. Ruido de pacote corrompido
    (mSBC/alt quebrado) e broadband e preenche a banda alta tambem.
    Usa media movel como passa-baixa grosseiro: HF ~= sinal - passa_baixa.
    """
    win = max(1, int(rate / 1000.0))  # ~1 ms
    n = len(v)
    if n < win * 4:
        return None
    acc = 0
    lp = [0.0] * n
    for i in range(n):
        acc += v[i]
        if i >= win:
            acc -= v[i - win]
        lp[i] = acc / win
    lo = 0.0
    hf = 0.0
    for i in range(n):
        d = v[i] - lp[i]
        hf += d * d
        lo += lp[i] * lp[i]
    if hf <= 0:
        return None
    return (lo / n) / (hf / n)


def analyze(path, window_ms=50.0):
    rate, v = read_wav_mono(path)
    if not v:
        return None
    win = max(1, int(rate * window_ms / 1000.0))
    frames = [v[i : i + win] for i in range(0, len(v), win)]
    frames = [f for f in frames if f]
    rms = [math.sqrt(sum(x * x for x in f) / len(f)) for f in frames]
    absmax = max(abs(x) for x in v)
    clipped = sum(1 for x in v if abs(x) >= 32500)

    ordered = sorted(rms)
    p05 = ordered[max(0, int(len(ordered) * 0.05) - 1)]
    p50 = ordered[max(0, int(len(ordered) * 0.50) - 1)]
    p95 = ordered[min(len(ordered) - 1, int(len(ordered) * 0.95))]
    peak_frame = max(rms) if rms else 0.0

    # floor = 5o percentil; sinal = frames acima de 4x o floor
    floor = p05
    thr = max(floor * 4.0, 12.0)
    active = [r > thr for r in rms]
    frac_active = sum(active) / len(active) if active else 0.0

    # maior sequencia de silencio (dropout) em segundos
    longest = cur = 0
    for a in active:
        if a:
            cur = 0
        else:
            cur += 1
            longest = max(longest, cur)
    longest_s = longest * window_ms / 1000.0

    snr = 20 * math.log10(peak_frame / floor) if floor > 0 and peak_frame > 0 else 0.0
    # quando o floor e exatamente 0 (silencio digital), SNR e infinito -> marca
    floor_is_zero = floor < 0.5

    return {
        "file": path,
        "rate": rate,
        "dur_s": len(v) / rate,
        "absmax": absmax,
        "clipped": clipped,
        "floor_p05": floor,
        "p50": p50,
        "p95": p95,
        "snr_db": snr,
        "frac_active": frac_active,
        "longest_silence_s": longest_s,
    }


if __name__ == "__main__":
    for p in sys.argv[1:]:
        r = analyze(p)
        if not r:
            print(f"{p}: VAZIO")
            continue
        print(f"\n=== {r['file']} ===")
        print(f"  dur={r['dur_s']:.1f}s rate={r['rate']}")
        print(f"  absmax={r['absmax']}  clip={r['clipped']}")
        print(f"  floor(p05)={r['floor_p05']:.1f}  p50={r['p50']:.1f}  p95={r['p95']:.1f}")
        print(f"  SNR(peak/floor)={r['snr_db']:.1f} dB")
        print(f"  frames com sinal={100*r['frac_active']:.1f}%")
        print(f"  maior silencio interno={r['longest_silence_s']:.2f}s")
        # Veredito: este arquivo e um PRE-FILTRO, nao o veredito final.
        # So marca FALHA em casos duros (nada captado / esparso / so ruido).
        # Pausas naturais da fala geram buracos de 1-2s e nao sao defeito —
        # por isso buraco vira INFORMAÇÃO, nao reprovação.
        if r["absmax"] < 200:
            v = "FALHA_SILENCIO (nada captado)"
        elif r["frac_active"] < 0.20:
            v = "FALHA_ESCASO (voz muito esparsa)"
        elif r["p95"] < 300:
            v = "FALHA_SO_RUIDO (p95 baixo)"
        elif r["longest_silence_s"] > 1.5:
            v = f"OK_COM_PAUSAS (maior buraco {r['longest_silence_s']:.1f}s — normal em fala)"
        else:
            v = "OK_PARA_TRANSCRICAO"
        print(f"  VEREDICTO_ANALISE={v}")
        print("  (pre-filtro apenas; o veredito real e a transcricao)")

