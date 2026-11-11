#!/usr/bin/env python3
"""Procedural sound and music synthesizer for Crowns of Caern.

Every sound in assets/audio/ is rendered by this script from code: no samples,
no third-party recordings, so the output is wholly original and owned by the
project (see assets/audio/LICENSES.md). Rendering is deterministic (fixed seeds).

    python3 tools/audio/synth.py build [name ...]   # render all (or some) sounds to .ogg
    python3 tools/audio/synth.py list               # list sound names

Needs numpy and ffmpeg with libvorbis. Only the build needs them: the game and
the tests use the committed .ogg files.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 32000
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "audio")

# ----------------------------------------------------------------- basics --


def t_axis(dur: float) -> np.ndarray:
    return np.arange(int(dur * SR)) / SR


def midi_hz(m: float) -> float:
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


# Render context. "variant" reseeds every generator (another take of the same sound: new noise, phases, small
# timing and tone differences), "faction" adds that faction's colour to the events that carry flavour, and
# "rich" switches on the overtone layers (False renders the original, plainer instruments).
CTX = {"variant": 0, "faction": None, "rich": True}


def rng(seed: int) -> np.random.Generator:
    return np.random.default_rng(seed + 7919 * CTX["variant"])


def env_adsr(n: int, a: float, d: float, s: float, r: float) -> np.ndarray:
    """Attack/decay/sustain-level/release envelope over n samples (times in s)."""
    e = np.full(n, s, dtype=np.float64)
    na, nd, nr = int(a * SR), int(d * SR), int(r * SR)
    na = min(na, n)
    if na > 0:
        e[:na] = np.linspace(0, 1, na, endpoint=False) ** 1.5
    nd = min(nd, n - na)
    if nd > 0:
        e[na:na + nd] = np.linspace(1, s, nd)
    nr = min(nr, n)
    if nr > 0:
        e[n - nr:] *= np.linspace(1, 0, nr) ** 2
    return e


def exp_decay(n: int, tau: float) -> np.ndarray:
    return np.exp(-np.arange(n) / (tau * SR))


def fft_filter(x: np.ndarray, resp) -> np.ndarray:
    """Zero-phase filter: multiplies the spectrum by resp(freqs)."""
    n = len(x)
    if n == 0:
        return x
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    return np.fft.irfft(X * resp(f), n)


def lowpass(x, fc, order=2):
    return fft_filter(x, lambda f: 1 / np.sqrt(1 + (f / fc) ** (2 * order)))


def highpass(x, fc, order=2):
    return fft_filter(x, lambda f: 1 / np.sqrt(1 + (fc / np.maximum(f, 1e-3)) ** (2 * order)))


def bandpass(x, fc, q=2.0):
    return fft_filter(x, lambda f: 1 / np.sqrt(1 + (q * (f / fc - fc / np.maximum(f, 1e-3))) ** 2))


def formants(x, peaks):
    """Adds resonant bumps (vowel-like colour) on top of a gentle lowpass."""
    def resp(f):
        r = 0.25 / np.sqrt(1 + (f / 900) ** 2)
        for fc, q, g in peaks:
            r = r + g / np.sqrt(1 + (q * (f / fc - fc / np.maximum(f, 1e-3))) ** 2)
        return r
    return fft_filter(x, resp)


def mix(*xs: np.ndarray) -> np.ndarray:
    """Sums signals of different lengths (padding the shorter ones)."""
    out = np.zeros(max(len(x) for x in xs))
    for x in xs:
        out[: len(x)] += x
    return out


def norm(x: np.ndarray, peak: float = 0.9) -> np.ndarray:
    m = np.max(np.abs(x)) if len(x) else 0
    return x * (peak / m) if m > 0 else x


def place(buf: np.ndarray, sig: np.ndarray, start: float, gain: float = 1.0, wrap: bool = False) -> None:
    if CTX["variant"] and start > 0 and not wrap:  # another take: layers land a few milliseconds off
        start = max(0.0, start + 0.012 * (((start * 1000 + CTX["variant"] * 377) * 0.618034) % 1.0 - 0.5) * 2)
    i = int(start * SR)
    n = len(sig)
    if wrap:
        idx = (np.arange(n) + i) % len(buf)
        np.add.at(buf, idx, sig * gain)
    else:
        end = min(len(buf), i + n)
        if end > i:
            buf[i:end] += sig[:end - i] * gain


def reverb(x: np.ndarray, decay: float, mix: float, seed: int, tone: float = 4000, circular: bool = False,
           predelay: float = 0.02) -> np.ndarray:
    """Convolution with a synthetic decaying-noise impulse (a stone hall)."""
    r = rng(seed)
    n_ir = int(min(decay * 1.6, 8.0) * SR)
    ir = r.standard_normal(n_ir) * exp_decay(n_ir, decay / 6.9 * 1.0)
    ir = lowpass(ir, tone, 1)
    ir[: int(predelay * SR)] = 0
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    if circular:
        n = len(x)
        irc = np.zeros(n)
        k = min(n, n_ir)
        irc[:k] = ir[:k]
        wet = np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(irc), n)
        return x * (1 - mix) + wet * mix * 2.2
    n = len(x) + n_ir
    wet = np.fft.irfft(np.fft.rfft(x, n) * np.fft.rfft(ir, n), n)
    dry = np.concatenate([x, np.zeros(n_ir)])
    out = dry * (1 - mix) + wet * mix * 2.2
    # trim the silent tail
    thr = np.max(np.abs(out)) * 1e-3
    nz = np.nonzero(np.abs(out) > thr)[0]
    return out[: nz[-1] + 1] if len(nz) else out


def fade_out(x: np.ndarray, dur: float) -> np.ndarray:
    n = min(len(x), int(dur * SR))
    x = x.copy()
    x[len(x) - n:] *= np.linspace(1, 0, n) ** 2
    return x


def soft_clip(x: np.ndarray, drive: float = 1.0) -> np.ndarray:
    return np.tanh(x * drive) / np.tanh(drive)


# ------------------------------------------------------------ instruments --


def saw(freq, t, harmonics=None, detune_lfo=0.0, phase=0.0):
    """Band-limited sawtooth (additive)."""
    nh = harmonics or max(1, int(SR / 2 / max(freq, 1) * 0.8))
    nh = min(nh, 60)
    vib = 1 + detune_lfo * np.sin(2 * np.pi * 5.1 * t + phase)
    ph = 2 * np.pi * freq * np.cumsum(vib) / SR + phase
    out = np.zeros_like(t)
    for k in range(1, nh + 1):
        out += np.sin(k * ph) / k
    return out * 0.6


def sine(freq, t, phase=0.0):
    return np.sin(2 * np.pi * freq * t + phase)


def _twin(fr, t, ph, beat_hz):
    """A partial plus a slightly mistuned twin: the slow beating makes bells and iron shimmer."""
    return np.sin(2 * np.pi * fr * t + ph) + 0.5 * np.sin(2 * np.pi * (fr + beat_hz) * t + ph * 1.7)


def choir_voice(m, dur, seed, vowel="ah", amp=1.0):
    """Dark ensemble voice: detuned saws through vowel formants, slow swell."""
    r = rng(seed)
    t = t_axis(dur)
    f = midi_hz(m)
    x = np.zeros_like(t)
    rich = CTX["rich"]
    for _ in range(6 if rich else 4):
        det = 1 + r.uniform(-0.006, 0.006)
        x += saw(f * det, t, harmonics=24, detune_lfo=0.003, phase=r.uniform(0, 6.28))
    if rich:  # a quiet head-voice an octave up: upper overtones the formants can catch
        x += 0.25 * saw(f * 2 * (1 + r.uniform(-0.004, 0.004)), t, harmonics=12, detune_lfo=0.004, phase=r.uniform(0, 6.28))
    peaks = {"ah": [(650, 4, 1.0), (1080, 5, 0.6), (2650, 6, 0.25)],
             "oh": [(420, 4, 1.0), (800, 5, 0.5), (2600, 6, 0.15)],
             "oo": [(320, 4, 1.0), (700, 5, 0.3), (2400, 6, 0.08)]}[vowel]
    x = formants(x, peaks)
    if rich:  # breath through the same vowel
        x += norm(formants(r.standard_normal(len(t)), peaks), np.max(np.abs(x)) * 0.1)
    x *= env_adsr(len(t), min(1.6, dur * 0.4), 0.5, 0.85, min(1.8, dur * 0.4))
    x *= 1 + 0.12 * np.sin(2 * np.pi * r.uniform(0.15, 0.3) * t)
    return norm(x, 0.3 * amp)


def string_pad(m, dur, seed, bright=1800, amp=1.0):
    r = rng(seed)
    t = t_axis(dur)
    f = midi_hz(m)
    x = np.zeros_like(t)
    for _ in range(3):
        x += saw(f * (1 + r.uniform(-0.004, 0.004)), t, detune_lfo=0.002, phase=r.uniform(0, 6.28))
    if CTX["rich"]:  # octave and twelfth an ensemble adds, plus bow hiss riding the bright band
        x += 0.22 * saw(f * 2 * (1 + r.uniform(-0.003, 0.003)), t, harmonics=16, detune_lfo=0.003, phase=r.uniform(0, 6.28))
        x += 0.08 * sine(f * 3, t, r.uniform(0, 6.28)) * (1 + 0.5 * np.sin(2 * np.pi * 0.23 * t))
        x += norm(bandpass(r.standard_normal(len(t)), min(bright * 1.5, 6000), 1.2), 0.06)
    x = lowpass(x, bright, 2)
    x *= env_adsr(len(t), min(1.2, dur * 0.35), 0.3, 0.9, min(1.5, dur * 0.4))
    return norm(x, 0.3 * amp)


def organ(m, dur, amp=1.0, stops=(1.0, 0.7, 0.35, 0.3, 0.12, 0.1)):
    t = t_axis(dur)
    f = midi_hz(m)
    ratios = (0.5, 1, 2, 3, 4, 6)
    x = np.zeros_like(t)
    for ratio, g in zip(ratios, stops):
        if f * ratio < SR / 2:
            x += g * np.sin(2 * np.pi * f * ratio * t + ratio)
    if CTX["rich"]:  # mixture stops (fifth and tierce ranks) and the pipe's attack chiff
        for ratio, g in ((1.5, 0.12), (5, 0.07), (8, 0.05)):
            if f * ratio < SR / 2:
                x += g * np.sin(2 * np.pi * f * ratio * 1.0007 * t + ratio)
        x += norm(bandpass(rng(int(m * 13)).standard_normal(len(t)), min(f * 4, 7000), 3), 0.35) * exp_decay(len(t), 0.05)
    x *= 1 + 0.03 * np.sin(2 * np.pi * 5.5 * t)
    x *= env_adsr(len(t), 0.08, 0.2, 0.85, min(0.6, dur * 0.3))
    return norm(x, 0.25 * amp)


def bell(m, dur=4.0, amp=1.0, bright=1.0, seed=0):
    """Inharmonic church/funeral bell."""
    r = rng(seed)
    t = t_axis(dur)
    f = midi_hz(m)
    partials = [(0.5, 1.0, 1.0), (1.0, 0.8, 0.7), (1.19, 0.6, 0.5), (1.56, 0.45, 0.4), (2.0, 0.5, 0.35),
                (2.51, 0.3 * bright, 0.25), (2.66, 0.25 * bright, 0.2), (3.01, 0.2 * bright, 0.15),
                (4.1, 0.12 * bright, 0.1), (5.4, 0.08 * bright, 0.06)]
    rich = CTX["rich"]
    if rich:
        partials += [(6.79, 0.06 * bright, 0.04), (8.3, 0.04 * bright, 0.03)]
    x = np.zeros_like(t)
    for ratio, g, tau in partials:
        fr = f * ratio * (1 + r.uniform(-0.002, 0.002))
        if fr < SR / 2:
            ph = r.uniform(0, 6.28)
            tone = _twin(fr, t, ph, r.uniform(0.6, 2.2)) if rich else np.sin(2 * np.pi * fr * t + ph)
            x += g * tone * exp_decay(len(t), tau * dur * 0.5)
    strike = r.standard_normal(len(t)) * exp_decay(len(t), 0.004)
    x += bandpass(strike, f * 3, 1.5) * 0.3
    x *= np.minimum(1, np.arange(len(t)) / (0.002 * SR))
    return norm(x, 0.4 * amp)


def pluck(m, dur=2.0, amp=1.0, bright=3000, seed=0):
    """Harp/lute-like pluck: decaying harmonics, higher ones fade faster."""
    r = rng(seed)
    t = t_axis(dur)
    f = midi_hz(m)
    x = np.zeros_like(t)
    for k in range(1, 16):
        if f * k > min(bright * 2, SR / 2):
            break
        g = (1 / k) * (0.6 if k % 2 == 0 else 1.0)
        x += g * np.sin(2 * np.pi * f * k * (1 + 0.0004 * k) * t + r.uniform(0, 6.28)) * exp_decay(len(t), dur * 0.35 / (1 + 0.5 * k))
    if CTX["rich"]:
        # wooden body resonances, the pick's scrape, and a sympathetic string ringing a twelfth above
        x += 0.5 * fft_filter(x, lambda fr: 1 / np.sqrt(1 + (3 * (fr / 240 - 240 / np.maximum(fr, 1e-3))) ** 2)
                              + 0.6 / np.sqrt(1 + (4 * (fr / 620 - 620 / np.maximum(fr, 1e-3))) ** 2))
        x += norm(highpass(r.standard_normal(len(t)), 2500, 2), 0.12) * exp_decay(len(t), 0.006)
        if f * 3 < SR / 2:
            x += 0.07 * np.sin(2 * np.pi * f * 3.001 * t) * exp_decay(len(t), dur * 0.4) * (1 - exp_decay(len(t), 0.08))
    x *= np.minimum(1, np.arange(len(t)) / (0.003 * SR))
    return norm(x, 0.35 * amp)


def drum(m=40, dur=1.2, amp=1.0, seed=0, snap=0.4, drop=1.6, tau=0.25):
    """War drum / timpani: falling sine body plus a filtered noise skin."""
    r = rng(seed)
    t = t_axis(dur)
    f0 = midi_hz(m)
    f = f0 * (1 + (drop - 1) * np.exp(-t / 0.03))
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * exp_decay(len(t), tau)
    body += 0.4 * np.sin(2 * np.pi * np.cumsum(f * 1.5) / SR) * exp_decay(len(t), tau * 0.5)
    if CTX["rich"]:  # the skin's higher circular modes (inharmonic) give the hit a wooden, tuned ring
        for ratio, g in ((1.59, 0.3), (2.14, 0.22), (2.30, 0.15), (2.65, 0.12), (2.92, 0.08)):
            body += g * np.sin(2 * np.pi * np.cumsum(f * ratio) / SR + r.uniform(0, 6.28)) * exp_decay(len(t), tau * 0.35 / ratio)
    skin = lowpass(r.standard_normal(len(t)), 1200, 2) * exp_decay(len(t), 0.03) * snap
    x = soft_clip(body + skin, 1.5)
    return norm(x, 0.6 * amp)


def horn(m, dur, amp=1.0, seed=0, bright=1400):
    """Dark brass: saw with an opening filter and a small pitch scoop."""
    t = t_axis(dur)
    rich = CTX["rich"]
    x = np.zeros_like(t)
    for det in ((1.0, 1.0035, 0.9968) if rich else (1.0,)):  # a section, not one player
        f = midi_hz(m) * det * (1 - 0.03 * np.exp(-t / 0.06))
        ph = 2 * np.pi * np.cumsum(f) / SR + (det * 40 if rich else 0.0)
        for k in range(1, 30):
            x += np.sin(k * ph) / k
    e = env_adsr(len(t), 0.09, 0.3, 0.75, min(0.5, dur * 0.4))
    # filter brightness follows the envelope (two-band crossfade)
    dark = lowpass(x, bright * 0.4, 2)
    brt = lowpass(x, bright * 1.6, 2)
    x = dark * (1 - e * 0.7) + brt * (e * 0.7)
    if rich:  # breath at the attack; louder brass gets brassier (more drive = more upper partials)
        x += norm(bandpass(rng(seed + 5).standard_normal(len(t)), 1300, 1.5), np.max(np.abs(x)) * 0.15) * exp_decay(len(t), 0.07)
        x = soft_clip(x * e * 1.4, 1.2)
    else:
        x = soft_clip(x * e * 1.4, 1.2)
    return norm(x, 0.3 * amp)


def noise_burst(dur, seed, fc, q=1.5, tau=0.05, amp=1.0, kind="band"):
    r = rng(seed)
    n = int(dur * SR)
    x = r.standard_normal(n)
    if kind == "band":
        x = bandpass(x, fc, q)
    elif kind == "low":
        x = lowpass(x, fc, 2)
    else:
        x = highpass(x, fc, 2)
    x *= exp_decay(n, tau) * np.minimum(1, np.arange(n) / (0.002 * SR))
    return norm(x, amp)


def metal(freq, dur, seed, amp=1.0, tau=0.4):
    """Struck iron: dense inharmonic partials."""
    r = rng(seed)
    t = t_axis(dur)
    x = np.zeros_like(t)
    rich = CTX["rich"]
    ratios = (1.0, 1.47, 2.09, 2.56, 3.39, 4.12, 5.3, 6.7)
    for ratio in ratios:
        fr = freq * ratio * (1 + r.uniform(-0.01, 0.01))
        if fr < SR / 2:
            ph = r.uniform(0, 6.28)
            tone = _twin(fr, t, ph, r.uniform(0.8, 3.0)) if rich else np.sin(2 * np.pi * fr * t + ph)
            x += tone * exp_decay(len(t), tau / ratio ** 0.5) / ratio ** 0.4
    x += noise_burst(dur, seed + 1, freq * 4, 1, 0.006, 0.6)
    return norm(x, 0.5 * amp)


def coin(seed, amp=1.0):
    r = rng(seed)
    return lowpass(metal(r.uniform(1700, 2600), 0.35, seed, amp, tau=0.12), 6000)


# ------------------------------------------------------- faction colour --
# A light faction dependency: events that carry flavour (finish(..., flavor=t)) get a short three-note motif in
# the faction's own voice and scale at time t, a quiet texture under the whole sound, and the faction's room.
# With no faction in CTX the sound is the shared, neutral version.


def _soft(x, attack=0.015, fc=3500):
    """Felt-mallet softening for the faction voices: rounded attack, no harsh top."""
    x = lowpass(x, fc, 2)
    return x * np.minimum(1, np.arange(len(x)) / (attack * SR))


def chapel(m, dur, amp=1.0, seed=0):
    """Quiet chapel organ (flutes only) with a small handbell on top."""
    x = mix(organ(m, dur * 0.7, 1.0, stops=(0.4, 1.0, 0.3, 0.08, 0, 0)), bell(m + 24, dur, 0.25, 0.5, seed=seed))
    return norm(_soft(x, 0.03, 3000), 0.3 * amp)


def flute(m, dur, amp=1.0, seed=0):
    """Wooden flute: near-sine with a little breath and a vibrato that blooms in."""
    r = rng(seed)
    t = t_axis(dur)
    f = midi_hz(m)
    ph = 2 * np.pi * f * np.cumsum(1 + 0.004 * np.sin(2 * np.pi * 5.2 * t) * np.minimum(1, t / 0.3)) / SR
    x = np.sin(ph) + 0.18 * np.sin(2 * ph) + 0.05 * np.sin(3 * ph)
    x += norm(bandpass(r.standard_normal(len(t)), f * 2, 3), 0.1)
    x *= env_adsr(len(t), 0.08, 0.15, 0.7, min(0.5, dur * 0.4))
    return norm(_soft(x, 0.04, 4000), 0.3 * amp)


def glass(m, dur, amp=1.0, seed=0):
    """Ice chime: a soft celesta-like bar with a faint shimmer."""
    r = rng(seed)
    t = t_axis(dur)
    f = midi_hz(m)
    x = np.zeros_like(t)
    for ratio, g, tau in ((1.0, 1.0, 0.6), (2.76, 0.25, 0.25), (5.4, 0.06, 0.1)):
        if f * ratio < SR / 2:
            x += g * _twin(f * ratio, t, r.uniform(0, 6.28), r.uniform(0.5, 1.5)) * exp_decay(len(t), tau * dur)
    return norm(_soft(x, 0.006, 5000), 0.3 * amp)


def gong(m, dur, amp=1.0, seed=0):
    """Sunken gong struck with a felt mallet: dark, round, its pitch sagging a little."""
    t = t_axis(dur)
    x = 0.4 * lowpass(metal(midi_hz(m), dur, seed, 1.0, tau=dur * 0.45), 900, 2)
    x += np.sin(2 * np.pi * np.cumsum(midi_hz(m - 12) * (1 - 0.015 * t / dur)) / SR) * exp_decay(len(t), dur * 0.35)
    return norm(_soft(x, 0.03, 1500), 0.35 * amp)


def ghost(m, dur, amp=1.0, seed=0):
    """Hollow voice: slightly out-of-tune sines that sag, through an "oo" mouth."""
    r = rng(seed)
    t = t_axis(dur)
    f = midi_hz(m)
    x = np.zeros_like(t)
    for _ in range(3):
        glide = f * (1 + r.uniform(-0.008, 0.008)) * (1 - 0.015 * t / dur)
        ph = 2 * np.pi * np.cumsum(glide) / SR
        x += np.sin(ph) + 0.2 * np.sin(2 * ph)
    x += norm(r.standard_normal(len(t)), 0.25)
    x = formants(x, [(320, 4, 1.0), (700, 5, 0.3), (2400, 6, 0.05)])
    x *= env_adsr(len(t), 0.2, 0.2, 0.7, min(0.7, dur * 0.5)) * (1 + 0.12 * np.sin(2 * np.pi * 2.5 * t))
    return norm(_soft(x, 0.05, 2200), 0.3 * amp)


def ember_horn(m, dur, amp=1.0, seed=0):
    """Warm, low brass swell with a faint tritone shadow: menace without noise."""
    x = horn(m, dur, 1.0, seed, bright=700) + 0.25 * horn(m - 6, dur, 1.0, seed + 1, bright=600)
    return norm(_soft(x, 0.06, 1800), 0.3 * amp)


def harp(m, dur, amp=1.0, seed=0):
    """Silver-strung harp: a clear pluck with a lightly doubled string."""
    x = mix(pluck(m, dur, 1.0, 2600, seed), pluck(m + 0.05, dur, 0.4, 2600, seed + 1))
    return norm(_soft(x, 0.004, 4000), 0.3 * amp)


def deep_chime(m, dur, amp=1.0, seed=0):
    """Deep-forge chime: a hammered bar heard from far down the halls."""
    x = mix(bell(m, dur, 1.0, 0.4, seed=seed), 0.3 * drum(36, 0.4, 0.4, seed + 1, snap=0.0, tau=0.08))
    return norm(_soft(x, 0.008, 2500), 0.3 * amp)


def _texture(kind, dur, seed):
    r = rng(seed)
    n = int(dur * SR)
    t = t_axis(dur)
    x = np.zeros(n)
    if kind == "embers":  # a hearth: low roar with a few soft pops
        x += norm(lowpass(r.standard_normal(n), 250, 2), 0.8)
        for k in range(int(dur * 6)):
            place(x, noise_burst(0.015, seed + k, r.uniform(800, 2000), 2, 0.003, r.uniform(0.1, 0.4)), r.uniform(0, dur))
    elif kind == "rattle":  # bones: clusters of dry clicks
        for c in range(int(dur * 3) + 1):
            at = r.uniform(0, dur)
            for k in range(r.integers(3, 7)):
                place(x, noise_burst(0.02, seed + c * 10 + k, r.uniform(900, 1600), 4, 0.006, r.uniform(0.3, 0.7)),
                      at + k * r.uniform(0.02, 0.05))
    elif kind == "leaves":  # rustle that breathes in and out
        x += norm(bandpass(r.standard_normal(n), 2200, 0.8), 0.6) * (0.5 + 0.5 * np.sin(2 * np.pi * 1.3 * t) ** 2)
    elif kind == "rumble":  # deep earth
        x += norm(lowpass(r.standard_normal(n), 110, 2), 1.0)
    elif kind == "wind":  # a whistling gust whose band sweeps
        noise = r.standard_normal(n)
        lo, hi = bandpass(noise, 500, 5), bandpass(noise, 900, 5)
        w = 0.5 + 0.5 * np.sin(2 * np.pi * 0.4 * t)
        x += norm(lo * (1 - w) + hi * w, 0.8)
    elif kind == "whisper":  # hushed sibilance in short phrases
        hiss = formants(r.standard_normal(n), [(2200, 3, 1.0), (3600, 4, 0.4)])
        x += norm(hiss, 0.7) * (0.5 + 0.5 * np.sin(2 * np.pi * 2.1 * t + r.uniform(0, 6.28))) ** 3
    elif kind == "bubbles":  # rising bubble chirps
        for k in range(int(dur * 9)):
            bd = r.uniform(0.03, 0.08)
            tb = t_axis(bd)
            f0 = r.uniform(250, 700)
            ph = 2 * np.pi * np.cumsum(f0 * (1 + 2.5 * tb / bd)) / SR
            place(x, np.sin(ph) * exp_decay(len(tb), bd / 3) * r.uniform(0.3, 1), r.uniform(0, dur))
    x *= np.minimum(1, np.arange(n) / (0.05 * SR))
    return fade_out(x, min(0.4, dur * 0.4))


FACTIONS = {
    # voice, root (midi) and mode of the motif (scale degrees), texture, reverb room and tone multipliers
    "concord":    dict(voice=chapel, root=55, scale="dorian", motif=(0, 2, 4), step=0.22, texture=None,
                       room=1.3, tone=1.0),
    "ashen":      dict(voice=ember_horn, root=40, scale="phrygian_dom", motif=(0, 1, 0), step=0.24, texture="embers",
                       room=1.0, tone=0.75),
    "hollow":     dict(voice=ghost, root=62, scale="phrygian", motif=(4, 1, 0), step=0.28, texture="rattle",
                       room=1.6, tone=0.7),
    "thornwood":  dict(voice=flute, root=69, scale="dorian", motif=(0, 1, 4), step=0.18, texture="leaves",
                       room=0.9, tone=1.0),
    "forge":      dict(voice=deep_chime, root=57, scale="harmonic", motif=(0, 4, 2), step=0.24, texture="rumble",
                       room=1.4, tone=0.8),
    "frostmarch": dict(voice=glass, root=79, scale="aeolian", motif=(0, 4, 7), step=0.18, texture="wind",
                       room=1.4, tone=1.15),
    "darkelf":    dict(voice=harp, root=68, scale="phrygian", motif=(4, 1, 0), step=0.16, texture="whisper",
                       room=1.2, tone=1.0),
    "fishmen":    dict(voice=gong, root=43, scale="aeolian", motif=(0, 2, 1), step=0.3, texture="bubbles",
                       room=1.3, tone=0.6),
}
FLAVOR_GAIN = 0.26  # motif level against the event's own peak: a colour, not a second sound
TEXTURE_GAIN = 0.045


def add_flavor(x, fac, at, seed):
    peak = np.max(np.abs(x)) if len(x) else 1.0
    step = fac["step"]
    n = max(len(x), int((at + step * 3 + 1.6) * SR))
    out = np.zeros(n)
    out[: len(x)] = x
    motif = np.zeros(n)
    for k, d in enumerate(fac["motif"]):
        place(motif, fac["voice"](degree(fac["root"], fac["scale"], d), 1.5, 1.0 - 0.15 * k, seed=seed + k), at + k * step)
    out += norm(motif, peak * FLAVOR_GAIN)
    if fac["texture"]:
        out += norm(_texture(fac["texture"], n / SR, seed + 50), peak * TEXTURE_GAIN)
    return out


# ----------------------------------------------------------------- sfx ---

SFX = {}


def sfx(name):
    def deco(fn):
        SFX[name] = fn
        return fn
    return deco


def finish(x, room=0.35, mix=0.18, seed=7, peak=0.85, tone=3500, flavor=None):
    """Reverb and level. flavor: time (s) at which the current faction's motif enters (None: no faction colour)."""
    fac = FACTIONS.get(CTX["faction"]) if flavor is not None else None
    if fac:
        x = add_flavor(x, fac, flavor, seed * 31 + 5)
        room, tone = room * fac["room"], tone * fac["tone"]
    if CTX["variant"]:  # each take sits a little brighter or darker in the room
        tone *= 0.82 + 0.36 * ((CTX["variant"] * 0.618034) % 1.0)
    if CTX["rich"]:  # the overtone layers live in the mids: round off the very top so nothing turns sharp
        x = lowpass(x, 7000, 1)
    return norm(fade_out(highpass(reverb(x, room, mix, seed, tone), 30), 0.01), peak)


@sfx("ui_click")
def _ui_click():
    x = mix(noise_burst(0.06, 1, 2200, 3, 0.006, 0.7), metal(1300, 0.08, 2, 0.4, tau=0.03),
            drum(60, 0.06, 0.5, 3, snap=0.2, tau=0.02))
    return finish(x, 0.25, 0.12, peak=0.55)


@sfx("ui_open")
def _ui_open():
    n = int(0.45 * SR)
    sweep = noise_burst(0.45, 4, 500, 1, 0.2, 0.5) * np.sin(np.linspace(0, np.pi, n)) ** 2
    x = mix(sweep, drum(38, 0.45, 0.8, 5, snap=0.5, tau=0.12))
    return finish(x, 0.6, 0.25, peak=0.6)


@sfx("ui_close")
def _ui_close():
    x = mix(drum(34, 0.35, 0.8, 6, snap=0.6, tau=0.08), noise_burst(0.3, 7, 300, 1, 0.05, 0.4))
    return finish(x, 0.5, 0.2, peak=0.55)


@sfx("ui_error")
def _ui_error():
    x = np.zeros(int(0.35 * SR))
    for i, s in enumerate((0.0, 0.13)):
        place(x, drum(45, 0.2, 0.9, 8 + i, snap=0.8, tau=0.04), s)
    x += lowpass(saw(midi_hz(38), t_axis(0.35)) * exp_decay(len(x), 0.08), 600) * 0.4
    return finish(x, 0.3, 0.1, peak=0.6)


def _step(seed, body_hz, noise_fc, q, tau, crunch=0.0, squelch=0.0, splash=0.0, click=0.0, crackle=0.0):
    r = rng(seed)
    dur = 0.32
    n = int(dur * SR)
    x = noise_burst(dur, seed, noise_fc, q, tau, 0.8)
    x += drum(body_hz, dur, 0.5, seed + 1, snap=0.1, drop=1.2, tau=0.04)
    if crunch:
        for k in range(10):
            g = noise_burst(0.02, seed + 10 + k, r.uniform(2500, 5000), 3, 0.004, crunch * r.uniform(0.3, 1))
            place(x, g, r.uniform(0.0, 0.09))
    if squelch:
        t = t_axis(dur)
        f = 180 + 500 * np.exp(-t / 0.05)
        sq = lowpass(np.sin(2 * np.pi * np.cumsum(f) / SR) * r.standard_normal(n) * 0.5 + np.sin(2 * np.pi * np.cumsum(f) / SR), 900)
        x += norm(sq * exp_decay(n, 0.07), squelch)
    if splash:
        sp = noise_burst(dur, seed + 30, 3000, 0.7, 0.1, splash)
        sp *= np.minimum(1, np.arange(n) / (0.015 * SR))
        x += sp
    if click:
        place(x, metal(r.uniform(900, 1300), 0.08, seed + 40, click, tau=0.02), 0.0)
    if crackle:
        for k in range(14):
            place(x, noise_burst(0.01, seed + 50 + k, r.uniform(1500, 6000), 2, 0.002, crackle * r.uniform(0.2, 1)),
                  r.uniform(0, 0.25))
    # Steps repeat every tile, so they stay short, low and soft.
    x = lowpass(highpass(x, 40), 3200, 2)
    return norm(fade_out(x[: int(0.2 * SR)], 0.06), 0.45)


STEPS = {
    "grass":    dict(body_hz=36, noise_fc=900, q=0.8, tau=0.05),
    "forest":   dict(body_hz=34, noise_fc=1600, q=0.6, tau=0.07, crunch=0.35),
    "desert":   dict(body_hz=32, noise_fc=4500, q=0.7, tau=0.09),
    "snow":     dict(body_hz=30, noise_fc=2500, q=0.9, tau=0.05, crunch=0.8),
    "swamp":    dict(body_hz=28, noise_fc=500, q=0.8, tau=0.08, squelch=0.8),
    "rock":     dict(body_hz=44, noise_fc=2200, q=1.2, tau=0.03, crunch=0.5, click=0.25),
    "road":     dict(body_hz=48, noise_fc=1500, q=2.0, tau=0.02, click=0.5),
    "ash":      dict(body_hz=30, noise_fc=1200, q=0.6, tau=0.06, crackle=0.7),
    "water":    dict(body_hz=26, noise_fc=1200, q=0.6, tau=0.06, splash=0.7),
}
for _k, _p in STEPS.items():
    for _v in (1, 2):
        SFX["step_%s_%d" % (_k, _v)] = (lambda p=_p, s=1000 + 100 * _v + sum(map(ord, _k)): _step(s, **p))


@sfx("pickup_gold")
def _pickup_gold():
    r = rng(20)
    x = np.zeros(int(0.9 * SR))
    for k in range(9):
        place(x, coin(200 + k, r.uniform(0.4, 1.0)), 0.03 + k * 0.045 + r.uniform(0, 0.02))
    place(x, drum(50, 0.3, 0.4, 21, snap=0.6, tau=0.04), 0.0)
    return finish(x, 0.5, 0.18, peak=0.6)


@sfx("pickup_resource")
def _pickup_resource():
    x = np.zeros(int(0.6 * SR))
    place(x, drum(33, 0.6, 1.0, 22, snap=0.9, tau=0.12), 0.0)
    place(x, noise_burst(0.3, 23, 700, 0.8, 0.06, 0.5), 0.0)
    place(x, metal(700, 0.4, 24, 0.3, tau=0.15), 0.04)
    return finish(x, 0.5, 0.2, peak=0.65)


@sfx("pickup_crystal")
def _pickup_crystal():
    x = np.zeros(int(1.4 * SR))
    for k, m in enumerate((86, 91, 93, 98)):
        place(x, bell(m, 1.2, 0.5, 1.5, seed=30 + k), k * 0.06)
    place(x, drum(40, 0.3, 0.4, 35, tau=0.05), 0)
    return finish(x, 1.0, 0.3, peak=0.55, tone=6000)


@sfx("capture_mine")
def _capture_mine():
    x = np.zeros(int(1.6 * SR))
    for k, s in enumerate((0.0, 0.32)):
        place(x, metal(420 - 60 * k, 1.0, 40 + k, 1.0, tau=0.5), s)
    place(x, drum(36, 0.8, 0.8, 43, tau=0.2), 0.0)
    for k in range(6):  # chain rattle
        place(x, metal(1800 + 150 * k, 0.12, 50 + k, 0.25, tau=0.04), 0.55 + k * 0.05)
    return finish(x, 1.0, 0.25, peak=0.7)


@sfx("capture_town")
def _capture_town():
    x = np.zeros(int(3.2 * SR))
    place(x, horn(43, 1.6, 1.0, 60), 0.0)
    place(x, horn(50, 1.6, 0.8, 61), 0.0)
    place(x, bell(55, 3.0, 0.7, seed=62), 0.9)
    place(x, drum(36, 1.0, 0.9, 63, tau=0.3), 0.0)
    return finish(x, 2.0, 0.35, peak=0.75, flavor=1.0)


@sfx("build")
def _build():
    """Timber and stone: three mallet knocks on wood, a heavy block settling, a warm chord as it stands."""
    x = np.zeros(int(2.2 * SR))
    for k in range(3):
        place(x, drum(47 - k, 0.35, 0.9 - 0.15 * k, 70 + k, snap=0.15, drop=1.15, tau=0.05), k * 0.3)
        place(x, noise_burst(0.12, 74 + k, 420, 2.5, 0.025, 0.35), k * 0.3)
    place(x, drum(29, 1.0, 1.0, 78, snap=0.25, tau=0.3), 0.95)
    place(x, lowpass(noise_burst(0.8, 79, 180, 0.7, 0.25, 0.5, kind="low"), 400), 0.95)
    for j, m in enumerate((45, 52, 57)):
        place(x, string_pad(m, 1.2, 75 + j, 900, 0.35), 1.0)
    return finish(lowpass(x, 2600, 2), 0.9, 0.25, peak=0.65, tone=2500, flavor=1.0)


@sfx("recruit")
def _recruit():
    x = np.zeros(int(1.5 * SR))
    for k in range(4):
        place(x, drum(41, 0.3, 0.9 if k % 2 == 0 else 0.6, 80 + k, snap=0.5, tau=0.07), k * 0.2)
    for k in range(8):  # armour clatter
        place(x, metal(1400 + 90 * k, 0.15, 90 + k, 0.2, tau=0.04), 0.08 + k * 0.09)
    place(x, horn(45, 0.7, 0.5, 99), 0.62)
    return finish(x, 0.7, 0.22, peak=0.7, flavor=0.7)


@sfx("upgrade")
def _upgrade():
    x = np.zeros(int(2.4 * SR))
    place(x, metal(760, 1.6, 100, 1.0, tau=0.8), 0.0)
    for k, m in enumerate((57, 60, 64)):
        place(x, choir_voice(m, 1.8, 101 + k, "oh"), 0.15)
    return finish(x, 1.6, 0.35, peak=0.7, flavor=0.25)


@sfx("hire_hero")
def _hire_hero():
    x = np.zeros(int(2.2 * SR))
    place(x, horn(50, 0.5, 0.8, 110), 0.0)
    place(x, horn(55, 1.0, 0.9, 111), 0.42)
    place(x, drum(38, 0.6, 0.7, 112, tau=0.15), 0.42)
    return finish(x, 1.2, 0.3, peak=0.7, flavor=0.45)


@sfx("trade")
def _trade():
    r = rng(120)
    x = np.zeros(int(0.9 * SR))
    for k in range(6):
        place(x, coin(121 + k, r.uniform(0.4, 0.9)), 0.02 + k * 0.06)
    place(x, metal(520, 0.6, 130, 0.4, tau=0.2), 0.42)  # scale pan
    return finish(x, 0.5, 0.2, peak=0.6)


@sfx("battle_prepare")
def _battle_prepare():
    x = np.zeros(int(2.4 * SR))
    for k, s in enumerate((0.0, 0.32, 1.1, 1.42)):  # heartbeat
        place(x, drum(31, 0.5, 1.0 if k % 2 == 0 else 0.7, 140 + k, snap=0.2, tau=0.12), s)
    place(x, string_pad(26, 2.4, 145, 400, 0.6), 0.0)
    return finish(x, 1.2, 0.25, peak=0.75)


@sfx("battle_start")
def _battle_start():
    x = np.zeros(int(3.0 * SR))
    place(x, horn(38, 1.4, 1.0, 150, bright=1100), 0.0)
    place(x, horn(45, 1.4, 0.7, 151, bright=1100), 0.0)
    for k in range(3):
        place(x, drum(33, 0.9, 1.0, 152 + k, snap=0.7, tau=0.25), 0.9 + k * 0.22)
    r = rng(155)
    for k in range(10):  # the clash
        place(x, metal(r.uniform(700, 1600), 0.6, 156 + k, r.uniform(0.3, 0.8), tau=0.2), 1.45 + r.uniform(0, 0.4))
    place(x, noise_burst(1.2, 170, 900, 0.6, 0.35, 0.5), 1.4)
    return finish(x, 1.6, 0.3, peak=0.8, flavor=0.5)


@sfx("hero_fallen")
def _hero_fallen():
    x = np.zeros(int(4.5 * SR))
    place(x, bell(36, 4.5, 1.0, 0.6, seed=180), 0)
    place(x, string_pad(24, 3.5, 181, 300, 0.7), 0.1)
    return finish(x, 2.5, 0.35, peak=0.75)


@sfx("town_lost")
def _town_lost():
    x = np.zeros(int(3.0 * SR))
    for k, s in enumerate((0.0, 0.9)):
        place(x, bell(41 - 2 * k, 2.5, 0.9, 0.7, seed=190 + k), s)
    return finish(x, 2.0, 0.35, peak=0.7)


@sfx("turn_begin")
def _turn_begin():
    x = bell(48, 3.5, 0.8, 0.8, seed=200)
    return finish(x, 2.2, 0.35, peak=0.55, flavor=0.3)


@sfx("week_begin")
def _week_begin():
    x = np.zeros(int(5.5 * SR))
    for k in range(3):
        place(x, bell(43, 3.5, 1.0, 0.7, seed=210 + k), k * 1.1)
    return finish(x, 2.8, 0.38, peak=0.7, flavor=0.4)


@sfx("level_up")
def _level_up():
    x = np.zeros(int(3.0 * SR))
    for k, m in enumerate((50, 57, 62, 66)):
        place(x, choir_voice(m, 2.4, 220 + k, "ah", 1.0), k * 0.08)
    place(x, bell(74, 2.5, 0.5, seed=226), 0.2)
    return finish(x, 2.0, 0.35, peak=0.7, flavor=0.45)


@sfx("encounter_good")
def _encounter_good():
    x = np.zeros(int(2.2 * SR))
    for k, m in enumerate((69, 74, 76, 81)):
        place(x, pluck(m, 1.6, 0.8, seed=230 + k), k * 0.11)
    return finish(x, 1.4, 0.3, peak=0.6)


@sfx("encounter_bad")
def _encounter_bad():
    x = np.zeros(int(2.2 * SR))
    for k, m in enumerate((62, 61, 56)):
        place(x, pluck(m, 1.6, 0.8, seed=240 + k), k * 0.16)
    place(x, string_pad(32, 1.8, 245, 500, 0.6), 0.3)
    return finish(x, 1.4, 0.3, peak=0.6)


# Battle sounds: played under the battle music while a fight is watched, so all of them stay low and soft.


@sfx("battle_hit")
def _battle_hit():
    """Muffled blade on shield, with the body of the blow."""
    r = rng(1300)
    x = mix(lowpass(metal(r.uniform(480, 760), 0.35, 1301, 0.7, tau=0.08), 2200, 2),
            drum(r.uniform(38, 44), 0.3, 0.9, 1302, snap=0.6, drop=1.3, tau=0.05),
            noise_burst(0.2, 1303, 500, 1.0, 0.03, 0.4))
    return finish(x, 0.6, 0.2, peak=0.5, tone=2400)


@sfx("battle_shot")
def _battle_shot():
    """Arrows or bolts leaving: a soft rising-falling whoosh and a thunk."""
    n = int(0.45 * SR)
    sweep = noise_burst(0.45, 1310, 1400, 1.2, 1.0, 0.6) * np.sin(np.linspace(0, np.pi, n)) ** 3
    x = mix(sweep, np.concatenate([np.zeros(int(0.3 * SR)), drum(50, 0.15, 0.5, 1311, snap=0.4, tau=0.02)]))
    return finish(lowpass(x, 3000), 0.5, 0.15, peak=0.45, tone=2600)


@sfx("battle_drums")
def _battle_drums():
    """A distant war-drum phrase across the field."""
    x = np.zeros(int(2.6 * SR))
    for k, (at, g) in enumerate(((0.0, 1.0), (0.42, 0.6), (0.84, 0.8), (1.05, 0.5), (1.26, 1.0))):
        place(x, drum(30, 1.0, g, 1320 + k, snap=0.3, tau=0.28), at)
    return finish(lowpass(x, 1500), 1.6, 0.35, peak=0.6, tone=1800)


@sfx("battle_horn")
def _battle_horn():
    """A war horn called from far behind the lines."""
    x = np.zeros(int(3.0 * SR))
    place(x, horn(45, 0.6, 0.8, 1330, bright=900), 0.0)
    place(x, horn(52, 1.6, 1.0, 1331, bright=900), 0.55)
    return finish(lowpass(x, 1400, 2), 2.4, 0.5, peak=0.55, tone=1500)


@sfx("weather_thunder")
def _weather_thunder():
    """Thunder over the field: a dry crack, then a long roll that rumbles in a few slow surges.
    Takes differ in crack strength, roll length and where the surges fall (near and distant strikes)."""
    v = CTX["variant"]
    r = rng(1400)
    dur = 6.5 + 1.2 * ((v * 0.618034) % 1.0)
    n = int(dur * SR)
    t = np.arange(n) / SR
    # The roll: deep noise whose loudness swells in uneven surges and dies away.
    roll = lowpass(r.standard_normal(n), 140, 2) + 0.35 * lowpass(r.standard_normal(n), 420, 2)
    surge = np.zeros(n)
    for k in range(5):
        at = 0.15 + k * (0.55 + 0.5 * r.random()) + 0.2 * r.random()
        width = 0.25 + 0.5 * r.random()
        surge += (0.55 + 0.45 * r.random()) * np.exp(-((t - at) / width) ** 2)
    roll *= (0.25 + surge) * np.exp(-t / (dur * 0.32)) * np.minimum(1, t / 0.08)
    # The crack: a short bright tear at the start (weaker on the distant takes).
    near = 1.0 - 0.75 * (v % 2)
    crack = mix(noise_burst(0.45, 1401, 2600, 0.7, 0.07, 1.0), noise_burst(0.3, 1402, 600, 0.8, 0.09, 0.8))
    x = norm(roll, 1.0)
    place(x, crack, 0.0, 0.55 * near, wrap=True)
    return finish(lowpass(x, 3000, 1), 2.2, 0.3, seed=1403, peak=0.8, tone=1200)


@sfx("weather_rain")
def _weather_rain():
    """Steady rain, a seamless loop: soft hiss on leaves and stone with scattered drops."""
    dur = 8.0
    n = int(dur * SR)
    r = rng(1410)
    hiss = bandpass(r.standard_normal(n), 3200, 0.6) * 0.5 + lowpass(r.standard_normal(n), 700, 1) * 0.35
    t = np.arange(n) / SR
    hiss *= 1.0 + 0.12 * np.sin(2 * np.pi * t / dur * 3) + 0.08 * np.sin(2 * np.pi * t / dur * 5 + 1.0)
    x = hiss.copy()
    for k in range(260):
        drop = noise_burst(0.05, 1420 + k % 40, 1800 + 3000 * r.random(), 3.0, 0.008, 0.5 + 0.5 * r.random())
        place(x, drop, r.random() * dur, 0.35, wrap=True)
    x = reverb(x, 0.8, 0.25, 1411, 3500, circular=True)  # wraps round, so the loop has no seam
    return norm(highpass(lowpass(x, 7000, 1), 60), 0.5)


# ---------------------------------------------------------------- music ---
# Loops are rendered circularly (notes and reverb wrap round the loop point)
# so they repeat without a seam.

SCALES = {
    "aeolian": [0, 2, 3, 5, 7, 8, 10],
    "phrygian": [0, 1, 3, 5, 7, 8, 10],
    "dorian": [0, 2, 3, 5, 7, 9, 10],
    "harmonic": [0, 2, 3, 5, 7, 8, 11],
    "phrygian_dom": [0, 1, 4, 5, 7, 8, 10],
}


def degree(root, scale, d):
    s = SCALES[scale]
    return root + s[d % 7] + 12 * (d // 7)


def triad(root, scale, d):
    return [degree(root, scale, d), degree(root, scale, d + 2), degree(root, scale, d + 4)]


MUSIC = {}


def music(name, loop=True, rich=False):
    """rich=False renders with the original, plainer instruments, so tracks made before the overtone layers keep
    their sound exactly."""
    def deco(fn):
        MUSIC[name] = (fn, loop, rich)
        return fn
    return deco


def master(buf, room, mix, seed, loop, tone=3000, flavor=None):
    fac = FACTIONS.get(CTX["faction"]) if flavor is not None else None
    if fac:
        buf = add_flavor(buf, fac, flavor, seed * 31 + 5)
        room, tone = room * fac["room"], tone * fac["tone"]
    if loop:
        x = reverb(buf, room, mix, seed, tone, circular=True)
    else:
        x = fade_out(reverb(buf, room, mix, seed, tone), 1.0)
    x = soft_clip(norm(highpass(x, 25), 1.0) * 1.1, 1.1)
    return norm(x, 0.8)


def felt_piano(m, dur=3.0, amp=1.0, seed=0):
    """Soft upright with felt on the hammers: slightly stretched partials, paired strings, a muted thump."""
    r = rng(seed)
    t = t_axis(dur)
    f = midi_hz(m)
    x = np.zeros_like(t)
    for k in range(1, 13):
        fk = f * k * np.sqrt(1 + 0.00015 * k * k)
        if fk > 5000:
            break
        g = 1 / k ** 1.4
        tau = dur * 0.45 / (1 + 0.35 * k)
        x += g * _twin(fk, t, r.uniform(0, 6.28), r.uniform(0.2, 0.7)) * exp_decay(len(t), tau)
    x += norm(lowpass(r.standard_normal(len(t)), 900, 2), 0.25) * exp_decay(len(t), 0.012)
    x *= np.minimum(1, np.arange(len(t)) / (0.006 * SR))
    return norm(lowpass(x, 3200, 2), 0.35 * amp)


def voiced(chord, center):
    """Close voicing of a chord (MIDI notes, any octave) nearest to center, so chords move smoothly."""
    best = None
    pcs = sorted({n % 12 for n in chord})
    for low in range(center - 9, center + 4):
        notes = []
        for pc in pcs:
            n = low + (pc - low) % 12
            notes.append(n)
        notes.sort()
        score = abs(sum(notes) / len(notes) - center) + (notes[-1] - notes[0]) * 0.3
        if best is None or score < best[0]:
            best = (score, notes)
    return best[1]


# chord names -> pitch classes, for the composed themes
CHORDS = {"Am": (9, 0, 4), "F": (5, 9, 0), "C": (0, 4, 7), "G": (7, 11, 2), "Dm": (2, 5, 9), "E": (4, 8, 11),
          "Em": (4, 7, 11), "Bb": (10, 2, 5), "A": (9, 1, 4), "Gm": (7, 10, 2)}


def bass_note(name, low=33):
    return low + (CHORDS[name][0] - low) % 12


@music("menu", rich=True)
def _m_menu():
    """Title theme in A minor: a felt-piano melody over broken chords and a soft string bed."""
    beat = 60 / 72
    bar = 4 * beat
    prog = ["Am", "F", "C", "G", "Am", "F", "Dm", "E", "F", "G", "C", "Am", "Dm", "Am", "E", "Am"]
    # (beat, MIDI note, length in beats) per bar: chord tones on the strong beats, steps between them
    melody = [[(0, 76, 2), (2, 72, 1), (3, 71, 1)], [(0, 69, 3), (3, 72, 1)], [(0, 67, 2), (2, 64, 1), (3, 67, 1)],
              [(0, 74, 3), (3, 71, 1)], [(0, 72, 2), (2, 71, 1), (3, 69, 1)], [(0, 72, 2), (2, 69, 2)],
              [(0, 74, 2), (2, 77, 1), (3, 76, 1)], [(0, 71, 2), (2, 68, 2)], [(0, 69, 2), (2, 72, 1), (3, 77, 1)],
              [(0, 74, 2), (2, 71, 2)], [(0, 76, 3), (3, 74, 1)], [(0, 72, 2), (2, 69, 2)],
              [(0, 77, 2), (2, 76, 1), (3, 74, 1)], [(0, 72, 2), (2, 76, 2)], [(0, 71, 2), (2, 68, 1), (3, 71, 1)],
              [(0, 69, 4)]]
    L = bar * len(prog)
    buf = np.zeros(int(L * SR))
    for i, name in enumerate(prog):
        t0 = i * bar
        pcs = CHORDS[name]
        pad = voiced(pcs, 58)
        for j, m in enumerate(pad):
            place(buf, string_pad(m, bar + 1.2, 1420 + i * 3 + j, 1100, 0.3), t0, wrap=True)
        b = bass_note(name)
        place(buf, string_pad(b, bar + 1.2, 1401 + i, 450, 0.75), t0, wrap=True)
        # left hand: root, fifth, octave, third, one per beat, soft
        arp = [b + 12, b + 12 + 7, b + 24, voiced(pcs, b + 28)[1]]
        for k, m in enumerate(arp):
            place(buf, felt_piano(m, 2.5, 0.42 if k == 0 else 0.3, seed=1500 + i * 4 + k), t0 + k * beat, wrap=True)
        for k, (at, m, ln) in enumerate(melody[i]):
            place(buf, felt_piano(m, max(2.0, ln * beat + 1.2), 0.85, seed=1450 + i * 4 + k), t0 + at * beat, wrap=True)
        if 8 <= i < 12:  # the choir joins softly in the third phrase, on the pad's upper notes
            for j, m in enumerate(pad[1:]):
                place(buf, choir_voice(m + 12, bar + 1.0, 1560 + i * 2 + j, "oo", 0.3), t0, wrap=True)
        if i in (0, 8):
            place(buf, bell(57, 5.0, 0.2, 0.5, seed=1540 + i), t0, wrap=True)
    return master(buf, 3.0, 0.38, 1580, True, tone=2600)


@music("map")
def _m_map():
    root, sc = 50, "aeolian"  # D
    prog = [0, 5, 3, 4, 0, 5, 6, 4]
    seg = 4.5
    L = seg * len(prog)
    buf = np.zeros(int(L * SR))
    r = rng(400)
    for i, d in enumerate(prog):
        chord = triad(root, sc, d)
        for j, m in enumerate(chord):
            place(buf, string_pad(m - 12, seg + 1.2, 401 + i * 3 + j, 1400, 0.55), i * seg, wrap=True)
        place(buf, string_pad(root - 24, seg + 1.2, 430 + i, 300, 0.8), i * seg, wrap=True)  # drone
        if i % 2 == 0:
            place(buf, drum(31, 1.5, 0.45, 440 + i, snap=0.2, tau=0.4), i * seg, wrap=True)
        # sparse lute melody on chord tones
        for k in range(3):
            if r.random() < 0.75:
                m = chord[r.integers(0, 3)] + 12 * r.integers(0, 2)
                place(buf, pluck(m, 2.2, 0.55, 2400, seed=450 + i * 5 + k), i * seg + k * 1.5 + 0.3, wrap=True)
    return master(buf, 3.0, 0.35, 470, True)


@music("map_highlands", rich=True)
def _m_map_highlands():
    """Map, second theme: open highlands. A wooden flute over a drone, plucked strings and a hand drum."""
    root, sc = 52, "dorian"  # E
    prog = [0, 3, 0, 6, 0, 3, 4, 0, 5, 3, 6, 0]
    seg = 4.5
    L = seg * len(prog)
    buf = np.zeros(int(L * SR))
    r = rng(1600)
    for i, d in enumerate(prog):
        chord = triad(root, sc, d)
        place(buf, string_pad(root - 24, seg + 1.2, 1601 + i, 300, 0.7), i * seg, wrap=True)  # drone
        place(buf, string_pad(root - 17, seg + 1.2, 1615 + i, 400, 0.35), i * seg, wrap=True)  # its fifth
        for j, m in enumerate(chord):
            place(buf, string_pad(m - 12, seg + 1.2, 1630 + i * 3 + j, 1200, 0.3), i * seg, wrap=True)
        for k in range(6):  # a lute picking the chord
            m = chord[[0, 1, 2, 1, 2, 1][k]] + (12 if k == 2 else 0)
            place(buf, pluck(m, 1.6, 0.45 if k % 3 == 0 else 0.3, 2200, seed=1670 + i * 6 + k), i * seg + k * seg / 6,
                  wrap=True)
        for k in (0, 2, 3):
            place(buf, drum(45, 0.4, 0.35 if k == 0 else 0.2, 1750 + i * 3 + k, snap=0.5, tau=0.06), i * seg + k * seg / 4,
                  wrap=True)
        if i % 4 in (1, 2):  # the flute sings in two of every four bars
            at = i * seg + 0.3
            for k in range(3):
                m = degree(root, sc, [4, 3, 2, 4, 5, 4, 2, 1, 0][(i * 3 + k) % 9]) + 12
                ln = [1.4, 0.9, 1.8][k]
                place(buf, flute(m, ln + 0.4, 0.8, seed=1790 + i * 3 + k), at, wrap=True)
                at += ln
    return master(buf, 2.8, 0.35, 1820, True, tone=2800)


@music("map_dusk", rich=True)
def _m_map_dusk():
    """Map, third theme: dusk over the marches. Felt piano and harp over low strings, slower."""
    root, sc = 48, "aeolian"  # C
    prog = [0, 5, 2, 6, 0, 3, 5, 4]
    seg = 6.0
    L = seg * len(prog)
    buf = np.zeros(int(L * SR))
    r = rng(1900)
    for i, d in enumerate(prog):
        chord = triad(root, sc, d)
        place(buf, string_pad(degree(root, sc, d) - 24, seg + 1.5, 1901 + i, 400, 0.9), i * seg, wrap=True)
        place(buf, string_pad(chord[1] - 12, seg + 1.5, 1915 + i, 800, 0.35), i * seg, wrap=True)
        for k in range(8):  # slow harp arpeggio
            m = chord[k % 3] + 12 * (k // 3)
            place(buf, pluck(m, 2.2, 0.35, 2600, seed=1930 + i * 8 + k), i * seg + k * 0.35, wrap=True)
        at = i * seg + 2.8
        for k in range(r.integers(2, 4)):
            m = chord[r.integers(0, 3)] + 12
            place(buf, felt_piano(m, 3.0, r.uniform(0.5, 0.8), seed=2000 + i * 4 + k), at, wrap=True)
            at += r.choice([0.75, 1.0, 1.5])
        if i % 4 == 3:
            place(buf, drum(31, 1.5, 0.35, 2040 + i, snap=0.2, tau=0.4), i * seg, wrap=True)
    return master(buf, 3.4, 0.4, 2060, True, tone=2400)


@music("town_concord")
def _m_town_concord():
    root, sc = 43, "dorian"  # G, a solemn hymn on the chapel organ
    prog = [0, 3, 4, 0, 5, 3, 6, 0]
    seg = 4.0
    L = seg * len(prog)
    buf = np.zeros(int(L * SR))
    melody = [7, 9, 8, 7, 9, 10, 11, 9]
    for i, d in enumerate(prog):
        for j, m in enumerate(triad(root, sc, d)):
            place(buf, organ(m + 12, seg + 0.3, 0.8), i * seg, wrap=True)
        place(buf, organ(degree(root, sc, d) - 12 + 12, seg + 0.3, 0.9, stops=(1.0, 0.6, 0.2, 0.1, 0, 0)), i * seg, wrap=True)
        place(buf, horn(degree(root, sc, melody[i]) + 12, seg * 0.9, 0.55, seed=500 + i, bright=1200), i * seg + 0.1, wrap=True)
        place(buf, drum(31, 1.2, 0.3, 520 + i, snap=0.1, tau=0.35), i * seg, wrap=True)
    return master(buf, 3.6, 0.42, 530, True)


@music("town_ashen")
def _m_town_ashen():
    root, sc = 40, "phrygian_dom"  # E, hellish
    seg = 3.0
    prog = [0, 1, 0, 6, 0, 1, 4, 1]
    L = seg * len(prog)
    buf = np.zeros(int(L * SR))
    beat = 60 / 76
    nbeats = int(L / beat)
    for b in range(nbeats):  # ritual drums
        place(buf, drum(29, 1.0, 1.0 if b % 4 == 0 else 0.55, 600 + b, snap=0.6, tau=0.2), b * beat, wrap=True)
        if b % 4 == 3:
            place(buf, drum(36, 0.5, 0.5, 700 + b, snap=0.9, tau=0.08), b * beat + beat * 0.5, wrap=True)
    for i, d in enumerate(prog):
        base = degree(root, sc, d)
        place(buf, string_pad(base - 12, seg + 1.0, 800 + i, 700, 0.9), i * seg, wrap=True)
        place(buf, string_pad(base - 6, seg + 1.0, 820 + i, 900, 0.35), i * seg, wrap=True)  # tritone smear
        place(buf, choir_voice(base + 12, seg + 1.2, 840 + i, "oh", 0.6), i * seg, wrap=True)
        if i % 2 == 1:
            place(buf, metal(180, 2.0, 860 + i, 0.4, tau=0.9), i * seg + 1.5, wrap=True)
    return master(buf, 2.4, 0.3, 880, True, tone=2400)


@music("town_default")
def _m_town_default():
    root, sc = 45, "aeolian"  # A, wild hearth: drone, frame drum, lute
    seg = 4.0
    prog = [0, 6, 5, 6, 0, 3, 4, 0]
    L = seg * len(prog)
    buf = np.zeros(int(L * SR))
    r = rng(900)
    step = seg / 8
    for i, d in enumerate(prog):
        chord = triad(root, sc, d)
        place(buf, string_pad(root - 12, seg + 1.0, 901 + i, 500, 0.8), i * seg, wrap=True)
        for k in range(8):
            m = chord[[0, 1, 2, 1, 0, 2, 1, 2][k]] + (12 if k in (2, 5) else 0)
            place(buf, pluck(m, 1.4, 0.6 if k % 2 == 0 else 0.4, 2200, seed=920 + i * 8 + k), i * seg + k * step, wrap=True)
        for k in (0, 3, 6):
            place(buf, drum(43, 0.5, 0.5 if k == 0 else 0.3, 990 + i * 3 + k, snap=0.5, tau=0.08), i * seg + k * step, wrap=True)
        if r.random() < 0.6:
            place(buf, choir_voice(chord[2], seg, 1000 + i, "oo", 0.5), i * seg, wrap=True)
    return master(buf, 2.0, 0.3, 1010, True)


@music("battle", rich=True)
def _m_battle():
    """Battle loop in D minor: low strings driving on root and fifth, drums, a choir, and a string melody that
    answers in the second and fourth phrases; the A-major chord pulls each phrase home."""
    beat = 60 / 100
    bar = 4 * beat
    prog = ["Dm", "Dm", "Bb", "Bb", "C", "C", "A", "A", "Dm", "Dm", "Gm", "Gm", "Bb", "C", "A", "A"]
    melody = {4: [(0, 67, 2), (2, 64, 2)], 5: [(0, 67, 1), (1, 69, 1), (2, 67, 2)], 6: [(0, 64, 3), (3, 61, 1)],
              7: [(0, 64, 4)], 12: [(0, 74, 2), (2, 70, 2)], 13: [(0, 72, 2), (2, 67, 2)],
              14: [(0, 73, 2), (2, 69, 2)], 15: [(0, 64, 2), (2, 69, 2)]}
    L = bar * len(prog)
    buf = np.zeros(int(L * SR))
    for i, name in enumerate(prog):
        t0 = i * bar
        pcs = CHORDS[name]
        b = bass_note(name, 36)
        fifth = b + 7
        for k, m in enumerate([b, b, b + 12, b, fifth, b, b + 12, fifth]):  # ostinato in eighths, root and fifth only
            place(buf, string_pad(m, beat * 0.55, 2100 + i * 8 + k, 1100, 0.5 if k % 2 == 0 else 0.33),
                  t0 + k * beat / 2, wrap=True)
        if i % 2 == 0 or prog[i] != prog[i - 1]:
            span = bar * (2 if i + 1 < len(prog) and prog[i + 1] == name else 1)
            for j, m in enumerate(voiced(pcs, 62)):
                place(buf, choir_voice(m, span + 0.8, 2470 + i * 3 + j, "oh", 0.3), t0, wrap=True)
            for j, m in enumerate(voiced(pcs, 55)):
                place(buf, string_pad(m, span + 0.8, 2440 + i * 3 + j, 900, 0.25), t0, wrap=True)
            place(buf, string_pad(b - 12, span + 0.8, 2520 + i, 350, 0.6), t0, wrap=True)
        for at, g in ((0, 1.0), (2, 0.75), (3.5, 0.45)):  # low drums
            place(buf, drum(31, 0.9, 0.55 * g, 2250 + i * 4 + int(at * 2), snap=0.25, tau=0.22), t0 + at * beat, wrap=True)
        for k in range(8):  # light frame drum
            place(buf, drum(47, 0.2, 0.15 if k % 2 else 0.08, 2330 + i * 8 + k, snap=0.5, tau=0.03), t0 + k * beat / 2,
                  wrap=True)
        if name == "A" and prog[i - 1] == "A":  # a short timpani roll into the return
            for k in range(6):
                place(buf, drum(33, 0.4, 0.15 + 0.06 * k, 2400 + i * 6 + k, snap=0.2, tau=0.1), t0 + 2.5 * beat + k * beat / 4,
                      wrap=True)
        for k, (at, m, ln) in enumerate(melody.get(i, [])):
            place(buf, string_pad(m, ln * beat + 0.5, 2540 + i * 4 + k, 1700, 0.55), t0 + at * beat, wrap=True)
    return master(buf, 2.2, 0.3, 2580, True, tone=2600)


@music("battle_victory", loop=False, rich=True)
def _m_victory():
    buf = np.zeros(int(9 * SR))
    for k in range(10):  # drum roll
        place(buf, drum(36, 0.4, 0.4 + k * 0.05, 1100 + k, snap=0.6, tau=0.08), k * 0.09)
    place(buf, drum(31, 2.0, 1.0, 1115, tau=0.5), 0.95)
    for j, m in enumerate((45, 52, 57, 61)):  # A major (picardy) over the minor build-up
        place(buf, horn(m, 4.5, 0.9 - j * 0.1, seed=1120 + j, bright=1600), 0.95)
    for j, m in enumerate((57, 61, 64, 69)):
        place(buf, choir_voice(m, 5.5, 1130 + j, "ah", 0.7), 1.0)
    place(buf, bell(69, 5.0, 0.5, seed=1140), 1.0)
    return master(buf, 3.0, 0.38, 1150, False, flavor=2.6)


@music("battle_defeat", loop=False)
def _m_defeat():
    buf = np.zeros(int(9 * SR))
    for i, m in enumerate((53, 52, 50, 49, 45)):
        place(buf, string_pad(m - 12, 2.4, 1200 + i, 900, 0.9), i * 1.2)
        place(buf, string_pad(m - 24, 2.4, 1210 + i, 400, 0.6), i * 1.2)
    place(buf, bell(33, 6.0, 1.0, 0.5, seed=1220), 5.6)
    return master(buf, 3.5, 0.4, 1230, False)


# ---------------------------------------------------------------- output --


def write_wav(path, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def encode(x, out_path, quality):
    ff = shutil.which("ffmpeg")
    if ff is None:
        sys.exit("ffmpeg (with libvorbis) is required to build audio")
    with tempfile.TemporaryDirectory() as td:
        wav = os.path.join(td, "x.wav")
        write_wav(wav, x)
        subprocess.run([ff, "-v", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", str(quality),
                        "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact", out_path], check=True)


# Extra takes of the busiest sounds (file name.ogg is take 1, name_2.ogg ... the others); the game rotates them.
TAKES = {"ui_click": 3, "pickup_gold": 3, "pickup_resource": 3, "capture_mine": 2, "build": 3, "recruit": 3,
         "trade": 2, "battle_hit": 4, "battle_shot": 3, "battle_drums": 2, "battle_horn": 2,
         "weather_thunder": 3}
# Events rendered once per faction (sfx/faction/<event>_<faction>.ogg), plus the victory stinger
# (music/battle_victory_<faction>.ogg). Must match faction_sounds in data/audio.json.
FACTION_EVENTS = ["capture_town", "build", "recruit", "upgrade", "hire_hero", "battle_start", "turn_begin",
                  "week_begin", "level_up"]
FACTION_MUSIC = ["battle_victory"]


def take_name(name, v):
    return name if v == 0 else "%s_%d" % (name, v + 1)


def render(fn, variant=0, faction=None, rich=True):
    CTX.update(variant=variant, faction=faction, rich=rich)
    try:
        return fn()
    finally:
        CTX.update(variant=0, faction=None, rich=True)


def build(names):
    for d in ("sfx", "sfx/faction", "music"):
        os.makedirs(os.path.join(OUT, d), exist_ok=True)
    for name, fn in SFX.items():
        if names and name not in names:
            continue
        for v in range(TAKES.get(name, 1)):
            x = render(fn, v)
            encode(x, os.path.join(OUT, "sfx", take_name(name, v) + ".ogg"), 4)
            print("sfx   %-26s %.2fs" % (take_name(name, v), len(x) / SR))
        if name in FACTION_EVENTS:
            for f in FACTIONS:
                x = render(fn, 0, f)
                encode(x, os.path.join(OUT, "sfx", "faction", "%s_%s.ogg" % (name, f)), 4)
                print("sfx   %-26s %.2fs" % ("faction/%s_%s" % (name, f), len(x) / SR))
    for name, (fn, loop, rich) in MUSIC.items():
        if names and name not in names:
            continue
        x = render(fn, 0, None, rich)
        encode(x, os.path.join(OUT, "music", name + ".ogg"), 3)
        print("music %-26s %.1fs%s" % (name, len(x) / SR, " loop" if loop else ""))
        if name in FACTION_MUSIC:
            for f in FACTIONS:
                x = render(fn, 0, f, rich)
                encode(x, os.path.join(OUT, "music", "%s_%s.ogg" % (name, f)), 3)
                print("music %-26s %.1fs" % ("%s_%s" % (name, f), len(x) / SR))


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "build"
    if cmd == "build":
        build(set(argv[2:]))
    elif cmd == "list":
        for n in list(SFX) + list(MUSIC):
            print(n)
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
