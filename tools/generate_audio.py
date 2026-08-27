#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""SHIBUYA RIFT のサウンドをプロシージャル合成する (要 numpy / 任意で ffmpeg)。

生成物 (game/assets/audio/ に出力・リポジトリにコミット済みなので通常は再実行不要):
  music_demo   60秒のシネマティック劇伴。デモのタイムラインに完全同期
               (平穏→裂け目braam→不穏パルス→バトル→撃破→死闘→増援ビルド→巨獣→決意)
  music_loop   フリープレイ用 32秒バトルループ
  rain_loop    雨環境音 (シームレスループ)
  slash / impact / spawn / rift / dissolve
  roar_kage / screech_ripper / roar_kaiju / footstep_kaiju

再生成:  py -3 tools\\generate_audio.py   (ffmpeg があれば ogg 化、無ければ wav)
"""

import shutil
import subprocess
import wave
from pathlib import Path

import numpy as np

SR = 44100
OUT = Path(__file__).resolve().parent.parent / "game" / "assets" / "audio"
rng = np.random.default_rng(20250827)


# ---------------------------------------------------------------- 基本部品

def tline(dur: float) -> np.ndarray:
    return np.arange(int(dur * SR)) / SR


def env_ar(n: int, a: float, r: float) -> np.ndarray:
    """attack/release 秒の簡易エンベロープ"""
    e = np.ones(n)
    na, nr = max(int(a * SR), 1), max(int(r * SR), 1)
    na, nr = min(na, n), min(nr, n)
    e[:na] = np.linspace(0, 1, na)
    e[-nr:] *= np.linspace(1, 0, nr)
    return e


def exp_decay(n: int, tau: float) -> np.ndarray:
    return np.exp(-np.arange(n) / (tau * SR))


def sine(freq, t):
    return np.sin(2 * np.pi * freq * t)


def saw(freq: float, t: np.ndarray, harmonics: int = 14) -> np.ndarray:
    out = np.zeros_like(t)
    for k in range(1, harmonics + 1):
        if freq * k > SR * 0.45:
            break
        out += sine(freq * k, t) / k
    return out * (2 / np.pi)


def noise(n: int) -> np.ndarray:
    return rng.standard_normal(n)


def fft_band(sig: np.ndarray, lo: float, hi: float) -> np.ndarray:
    """FFT でバンドパス (ブロック一括)"""
    spec = np.fft.rfft(sig)
    freqs = np.fft.rfftfreq(len(sig), 1 / SR)
    mask = (freqs >= lo) & (freqs <= hi)
    spec[~mask] = 0
    return np.fft.irfft(spec, len(sig))


def drive(sig: np.ndarray, amount: float = 2.0) -> np.ndarray:
    return np.tanh(sig * amount)


def add(buf: np.ndarray, sig: np.ndarray, at: float, gain: float = 1.0,
        pan: float = 0.0) -> None:
    """buf: (n,2)。pan -1..1"""
    i0 = int(at * SR)
    n = min(len(sig), len(buf) - i0)
    if n <= 0:
        return
    left = gain * (1 - max(pan, 0))
    right = gain * (1 + min(pan, 0))
    buf[i0:i0 + n, 0] += sig[:n] * left
    buf[i0:i0 + n, 1] += sig[:n] * right


def save(name: str, buf: np.ndarray, peak: float = 0.85) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    m = np.max(np.abs(buf)) or 1.0
    data = (buf / m * peak * 32767).astype(np.int16)
    wav_path = OUT / f"{name}.wav"
    with wave.open(str(wav_path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg:
        ogg_path = OUT / f"{name}.ogg"
        subprocess.run([ffmpeg, "-y", "-v", "error", "-i", str(wav_path),
                        "-c:a", "libvorbis", "-q:a", "5", str(ogg_path)], check=True)
        wav_path.unlink()
        print(f"  {name}.ogg ({ogg_path.stat().st_size / 1e3:.0f} kB)")
    else:
        print(f"  {name}.wav ({wav_path.stat().st_size / 1e6:.1f} MB) ※ffmpegでogg化推奨")


NOTE = {n: 440.0 * 2 ** ((i - 9) / 12) / 8 for i, n in enumerate(
    ["C", "Cs", "D", "Ds", "E", "F", "Fs", "G", "Gs", "A", "As", "B"])}  # オクターブ2基準


def nf(name: str, octave: int) -> float:
    return NOTE[name] * (2 ** (octave - 2))


# ---------------------------------------------------------------- 楽器

def pad_chord(freqs, dur, a=1.2, r=1.5, detune=0.4, gain=1.0):
    t = tline(dur)
    out = np.zeros_like(t)
    for f in freqs:
        for dt in (-detune, 0.0, detune):
            out += saw(f * (1 + dt / 100), t, 10)
        out += sine(f * 2, t) * 0.12
    out *= env_ar(len(t), a, r) / (len(freqs) * 3)
    return out * gain


def pluck(freq, dur=1.2, gain=1.0):
    t = tline(dur)
    return (sine(freq, t) + 0.4 * sine(freq * 2, t) + 0.15 * sine(freq * 3, t)) \
        * exp_decay(len(t), 0.35) * gain


def bass_note(freq, dur, gain=1.0):
    t = tline(dur)
    out = sine(freq, t) + 0.35 * sine(freq * 2, t) + 0.2 * saw(freq, t, 6)
    return drive(out, 1.6) * env_ar(len(t), 0.005, min(0.1, dur * 0.4)) * gain


def kick(gain=1.0):
    t = tline(0.35)
    f = 120 * np.exp(-t * 18) + 42
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * exp_decay(len(t), 0.12) * gain


def snare(gain=1.0):
    n = int(0.22 * SR)
    body = sine(190, tline(0.22)) * exp_decay(n, 0.05)
    hiss = fft_band(noise(n), 1500, 9000) * exp_decay(n, 0.07)
    return (body * 0.5 + hiss) * gain


def hat(gain=1.0):
    n = int(0.06 * SR)
    return fft_band(noise(n), 5500, 14000) * exp_decay(n, 0.018) * gain


def crash(gain=1.0, dur=1.8):
    n = int(dur * SR)
    return fft_band(noise(n), 3000, 13000) * exp_decay(n, dur * 0.35) * gain


def braam(root, dur=3.0, gain=1.0):
    t = tline(dur)
    out = np.zeros_like(t)
    for mult, g in [(0.5, 0.9), (1.0, 1.0), (1.5, 0.4), (2.0, 0.5), (2.02, 0.4)]:
        out += saw(root * mult, t, 12) * g
    out = drive(out, 2.2)
    swell = np.minimum(t / 0.25, 1.0) * np.exp(-np.maximum(t - dur * 0.35, 0) * 1.8)
    return out * swell * gain


def riser(dur=2.0, f0=300, f1=3000, gain=1.0):
    n = int(dur * SR)
    nz = fft_band(noise(n), f0, f1)
    return nz * np.linspace(0.05, 1.0, n) ** 1.6 * gain


def sub_boom(freq=34, dur=1.6, gain=1.0):
    t = tline(dur)
    return sine(freq, t) * exp_decay(len(t), dur * 0.3) * gain


# ---------------------------------------------------------------- 劇伴 (60秒)

def build_music_demo():
    print("music_demo (60s 劇伴) ...")
    total = 61.0
    buf = np.zeros((int(total * SR), 2))
    BPM = 128.0
    B = 60.0 / BPM  # 1拍

    dm = [nf("D", 2), nf("A", 2), nf("D", 3), nf("F", 3)]
    bb = [nf("As", 1), nf("F", 2), nf("As", 2), nf("D", 3)]
    cM = [nf("C", 2), nf("G", 2), nf("C", 3), nf("E", 3)]
    fM = [nf("F", 2), nf("C", 3), nf("F", 3), nf("A", 3)]

    # --- 0-8 平穏: 暗いパッド + まばらなプラック ---
    add(buf, pad_chord(dm, 8.5, a=2.5, r=2.0), 0.0, 0.32)
    for at, note, pan in [(1.2, nf("D", 4), -0.3), (3.1, nf("F", 4), 0.3),
                          (5.0, nf("A", 4), -0.2), (6.6, nf("E", 4), 0.25)]:
        add(buf, pluck(note, 1.6), at, 0.12, pan)
    # 裂け目へのライザー
    add(buf, riser(2.2, 200, 4000), 5.8, 0.5)

    # --- 8.0 裂け目: braam + サブ + クラッシュ ---
    add(buf, braam(nf("D", 1), 3.5), 8.0, 0.9)
    add(buf, sub_boom(30, 2.5), 8.0, 0.9)
    add(buf, crash(0.5, 2.5), 8.0, 0.5)

    # --- 10-20 不穏: 8分バスパルス + 半音トレモロ + ハーフキック ---
    tt = 10.0
    while tt < 19.8:
        add(buf, bass_note(nf("D", 1), B * 0.45), tt, 0.5)
        tt += B * 0.5
    trem_t = tline(10.0)
    trem = (sine(nf("A", 3), trem_t) + sine(nf("As", 3), trem_t)) \
        * (0.5 + 0.5 * sine(7.0, trem_t)) * env_ar(len(trem_t), 1.5, 1.5)
    add(buf, trem, 10.0, 0.05)
    for k in range(5):
        add(buf, kick(0.8), 10.0 + k * B * 2)
    add(buf, riser(1.6, 300, 5000), 18.2, 0.4)

    # --- 20-41.5 バトル: ドラム + オスティナート + スタブ ---
    bass_line = ["D", "D", "F", "D", "C", "D", "A", "C"]
    beat0 = 20.0
    n_beats = int((41.5 - beat0) / B)
    for i in range(n_beats):
        at = beat0 + i * B
        add(buf, kick(0.95), at)
        if i % 2 == 1:
            add(buf, snare(0.5), at)
        for h in range(2):
            add(buf, hat(0.16 if h == 0 else 0.1), at + h * B * 0.5, pan=0.35 if h else -0.35)
        step = bass_line[i % 8]
        add(buf, bass_note(nf(step, 1), B * 0.9), at, 0.55)
    # コードスタブ (2小節ごと Dm→Bb→C→Dm)
    prog = [dm, bb, cM, dm]
    for bar in range(0, int(n_beats / 4)):
        chord = prog[(bar // 2) % 4]
        add(buf, pad_chord([f * 2 for f in chord], B * 1.6, a=0.01, r=B), beat0 + bar * 4 * B, 0.16)
    # 30.4 撃破: クラッシュ + 上昇5度
    add(buf, crash(0.6), 30.4, 0.6)
    add(buf, pluck(nf("D", 4), 0.5), 30.4, 0.2)
    add(buf, pluck(nf("A", 4), 1.2), 30.7, 0.24)
    # 33.5- 鬼戦: Bbペダルで重く
    add(buf, pad_chord([nf("As", 1), nf("As", 2)], 8.0, a=0.5, r=1.5), 33.5, 0.2)

    # --- 41.5-46 増援ビルド: ドラム抜き → スネアロール + 半音上昇 ---
    for i, f0 in enumerate([nf("D", 3), nf("Ds", 3), nf("E", 3), nf("F", 3)]):
        add(buf, pad_chord([f0, f0 * 1.5], 1.2, a=0.05, r=0.6), 41.5 + i * 1.1, 0.2)
    # (スネアロール)
    roll_t = 42.5
    dt = 0.25
    while roll_t < 45.9:
        add(buf, snare(0.12 + (roll_t - 42.5) * 0.12), roll_t)
        dt = max(dt * 0.82, 0.07)
        roll_t += dt
    add(buf, riser(2.5, 200, 6000), 43.5, 0.55)

    # --- 46-52 巨獣: ハーフタイムの braam + サブブーム ---
    for k, at in enumerate([46.0, 48.0, 50.0]):
        add(buf, braam(nf("D", 1) if k % 2 == 0 else nf("C", 1), 2.4), at, 0.75)
        add(buf, sub_boom(32, 1.8), at, 0.8)
        add(buf, kick(0.9), at + 1.0)

    # --- 52-60 決意: 壮大な進行 Bb → F → C → Dm + ホーンメロディ ---
    prog2 = [(52.0, bb), (54.0, fM), (56.0, cM), (58.0, dm)]
    for at, chord in prog2:
        add(buf, pad_chord([f * 2 for f in chord], 2.6, a=0.25, r=1.2), at, 0.34)
        add(buf, bass_note(chord[0], 1.8), at, 0.5)
        add(buf, kick(0.7), at)
    horn = [(52.2, "D", 4, 1.6), (54.2, "C", 4, 1.6), (56.2, "A", 3, 1.4), (57.6, "D", 4, 2.6)]
    for at, note, octv, dur in horn:
        t = tline(dur)
        tone = (saw(nf(note, octv), t, 10) * 0.6 + sine(nf(note, octv), t) * 0.5) \
            * env_ar(len(t), 0.15, dur * 0.45)
        add(buf, tone, at, 0.2)
    add(buf, crash(0.5, 2.0), 58.0, 0.45)
    add(buf, sub_boom(30, 2.0), 58.0, 0.7)
    # 60でフェード完了
    fade_n = int(1.5 * SR)
    buf[-fade_n:] *= np.linspace(1, 0, fade_n)[:, None]
    save("music_demo", buf)


def build_music_loop():
    print("music_loop (32s フリープレイ) ...")
    BPM = 122.0
    B = 60.0 / BPM
    total = B * 64  # 16小節
    buf = np.zeros((int(total * SR) + 1, 2))
    dm = [nf("D", 2), nf("A", 2), nf("D", 3), nf("F", 3)]
    bb = [nf("As", 1), nf("F", 2), nf("As", 2), nf("D", 3)]
    prog = [dm, dm, bb, dm]
    bass_line = ["D", "D", "F", "D", "C", "D", "A", "C"]
    for i in range(64):
        at = i * B
        add(buf, kick(0.85), at)
        if i % 2 == 1:
            add(buf, snare(0.4), at)
        add(buf, hat(0.12), at + B * 0.5)
        add(buf, bass_note(nf(bass_line[i % 8], 1), B * 0.9), at, 0.5)
    # パッド
    for bar in range(16):
        add(buf, pad_chord([f * 2 for f in prog[(bar // 2) % 4]], B * 3.0, a=0.4, r=B), bar * 4 * B, 0.14)
    buf = buf[:int(total * SR)]
    save("music_loop", buf)


# ---------------------------------------------------------------- SFX

def build_sfx():
    print("SFX ...")
    # 雨ループ (シームレス)
    n = int(9.0 * SR)
    rain = fft_band(noise(n), 400, 9000) * 0.7 + fft_band(noise(n), 80, 400) * 0.3
    amp = 1.0 + 0.08 * sine(0.23, tline(9.0))
    rain *= amp
    xf = int(0.8 * SR)
    rain[:xf] = rain[:xf] * np.linspace(0, 1, xf) + rain[-xf:] * np.linspace(1, 0, xf)
    rain2 = np.stack([rain[:-xf], np.roll(rain[:-xf], 800)], axis=1)
    save("rain_loop", rain2, 0.5)

    # 斬撃
    n = int(0.3 * SR)
    sl = fft_band(noise(n), 1200, 9000) * exp_decay(n, 0.05)
    sweep_f = np.linspace(3000, 700, n)
    sl += np.sin(2 * np.pi * np.cumsum(sweep_f) / SR) * exp_decay(n, 0.04) * 0.5
    sl += sine(2400, tline(0.3)) * exp_decay(n, 0.12) * 0.2
    save("slash", np.stack([sl, sl], axis=1))

    # ヒット
    n = int(0.4 * SR)
    imp = sub_boom(58, 0.4, 1.0)[:n] + fft_band(noise(n), 150, 2500) * exp_decay(n, 0.06) * 0.8
    save("impact", np.stack([imp, imp], axis=1))

    # スポーン (逆ライザー + ザップ)
    n = int(0.7 * SR)
    sp = riser(0.45, 500, 6000)[::-1]
    sp = np.concatenate([sp, np.zeros(n - len(sp))])
    fm_t = tline(0.35)
    zap = np.sin(2 * np.pi * 700 * fm_t + 6 * np.sin(2 * np.pi * 90 * fm_t)) * exp_decay(len(fm_t), 0.1)
    sp[:len(zap)] += zap * 0.8
    save("spawn", np.stack([sp, sp], axis=1))

    # 裂け目 (4秒の巨大braam + ランブル)
    rift = braam(nf("Cs", 1), 4.0, 1.0)
    rmb = fft_band(noise(len(rift)), 25, 120) * env_ar(len(rift), 0.3, 2.0)
    rift = rift + rmb * 0.9
    save("rift", np.stack([rift, np.roll(rift, 500)], axis=1))

    # カゲオニ咆哮 (FMグロウル)
    t = tline(1.5)
    f = 95 * np.exp(-t * 0.7) + 40
    growl = np.sin(2 * np.pi * np.cumsum(f) / SR + 5.0 * np.sin(2 * np.pi * 33 * t))
    growl = drive(growl + fft_band(noise(len(t)), 200, 1200) * 0.3, 3.0) * env_ar(len(t), 0.06, 0.5)
    save("roar_kage", np.stack([growl, growl], axis=1))

    # リッパー金切り声
    t = tline(0.9)
    f = 1500 * np.exp(-t * 2.2) + 400 + 90 * sine(23, t)
    scr = np.sin(2 * np.pi * np.cumsum(f) / SR)
    scr = drive(scr + fft_band(noise(len(t)), 2000, 9000) * 0.25, 2.0) * env_ar(len(t), 0.03, 0.3)
    save("screech_ripper", np.stack([scr, scr], axis=1))

    # トシクイ咆哮 (3秒 サブ + 多層グロウル)
    t = tline(3.2)
    f = 50 * np.exp(-t * 0.4) + 26
    ka = np.sin(2 * np.pi * np.cumsum(f) / SR + 4.0 * np.sin(2 * np.pi * 17 * t))
    ka = drive(ka, 2.5) + sub_boom(30, 3.2)[:len(t)] * 0.8
    ka += fft_band(noise(len(t)), 100, 700) * env_ar(len(t), 0.4, 1.5) * 0.4
    ka *= env_ar(len(t), 0.15, 1.2)
    save("roar_kaiju", np.stack([ka, np.roll(ka, 700)], axis=1))

    # 巨獣の足音
    n = int(0.9 * SR)
    ft = sub_boom(36, 0.9)[:n] + fft_band(noise(n), 80, 500) * exp_decay(n, 0.1) * 0.5
    save("footstep_kaiju", np.stack([ft, ft], axis=1))

    # 消滅
    n = int(1.3 * SR)
    dis = fft_band(noise(n), 2000, 11000) * np.linspace(1, 0, n) ** 1.5
    tw_t = tline(1.3)
    for f0 in (1800, 2400, 3200):
        dis += sine(f0, tw_t) * exp_decay(n, 0.4) * 0.12
    save("dissolve", np.stack([dis, np.roll(dis, 300)], axis=1))


if __name__ == "__main__":
    build_music_demo()
    build_music_loop()
    build_sfx()
    print("完了:", OUT)
