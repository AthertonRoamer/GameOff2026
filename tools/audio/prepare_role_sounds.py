"""Turns the recordings in the Downloads folder into the game's weapon and impact sounds (16 bit mono wav, silence trimmed, a short fade at the end), standard library only.

  weapons/pistol_suppressed/  gunshot-with-silencer
  weapons/shotgun/            shotgun-shot-sfx
  weapons/shotgun_reload/     shotgun_cocking
  weapons/pistol_reload/      pistol-reloading (an mp3: decode it first with tools/audio/decode_mp3.gd; the click of the magazine coming out and
                              the one of it going in are kept and the silence between them is cut, so it fits the reload)
  impacts/ricochet/           metal-bullet-ricochets, cut into one clip for each ricochet

Run it from the project folder:   python tools/audio/prepare_role_sounds.py [folder with the downloads] [the decoded pistol reload wav]
Godot picks the files up (a SoundDef plays every file in its folder). Loudness and range are set in each SoundDef (game/audio/definitions).
"""
import math
import os
import struct
import sys
import wave

DOWNLOADS = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Downloads")
PISTOL_RELOAD_WAV = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.environ.get("TEMP", "."), "pistol_reload_raw.wav")
OUT = "game/audio/sounds"


def read(path):
    """mono floats and the sample rate, from a 16 or 24 bit wav"""
    with wave.open(path, "rb") as w:
        channels, width, rate, frames = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(frames)
    if width == 2:
        data = struct.unpack("<%dh" % (frames * channels), raw)
        scale = 32768.0
    elif width == 3:
        data = [int.from_bytes(raw[i:i + 3], "little", signed=True) for i in range(0, len(raw), 3)]
        scale = 8388608.0
    else:
        raise ValueError("%s: %d bit" % (path, width * 8))
    return [sum(data[i * channels:(i + 1) * channels]) / channels / scale for i in range(frames)], rate


def write(path, samples, rate, peak=0.9):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    top = max(max(abs(s) for s in samples), 1e-6)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(struct.pack("<%dh" % len(samples), *[int(max(-1.0, min(1.0, s / top * peak)) * 32767) for s in samples]))


def trim(samples, rate, threshold=0.02, lead=0.01, tail=0.06, fade=0.04):
    top = max(abs(s) for s in samples)
    limit = top * threshold
    first = next(i for i, s in enumerate(samples) if abs(s) > limit)
    last = len(samples) - next(i for i, s in enumerate(reversed(samples)) if abs(s) > limit)
    return fade_out(samples[max(0, first - int(lead * rate)):min(len(samples), last + int(tail * rate))], rate, fade)


def fade_out(samples, rate, seconds):
    n = min(int(seconds * rate), len(samples))
    out = list(samples)
    for i in range(n):
        out[len(out) - n + i] *= 1.0 - i / n
    return out


def envelope(samples, rate, window=0.01):
    step = int(window * rate)
    return [max(abs(s) for s in samples[i:i + step]) for i in range(0, len(samples), step)]


def save(folder, name, samples, rate):
    write(os.path.join(OUT, folder, name), samples, rate)
    print("%s/%s  %.2f s" % (folder, name, len(samples) / rate))


def clean_folder(folder):
    path = os.path.join(OUT, folder)
    if os.path.isdir(path):
        for file in os.listdir(path):
            if file.endswith(".wav"):
                os.remove(os.path.join(path, file))
                if os.path.exists(os.path.join(path, file + ".import")):
                    os.remove(os.path.join(path, file + ".import"))


def simple(source, folder, name):
    samples, rate = read(os.path.join(DOWNLOADS, source))
    save(folder, name, trim(samples, rate), rate)


simple("819269__hotpin7__gunshot-with-silencer.wav", "weapons/pistol_suppressed", "suppressed_01.wav")
simple("564480__lumikon__shotgun-shot-sfx.wav", "weapons/shotgun", "shotgun_01.wav")
simple("766107__luca2399__shotgun_cocking.wav", "weapons/shotgun_reload", "shotgun_reload_01.wav")

#the pistol's reload: the magazine out, a pause, the magazine in; the pause is cut down to a breath
samples, rate = read(PISTOL_RELOAD_WAV)
env = envelope(samples, rate)
loud = [i for i, e in enumerate(env) if e > 0.05 * max(env)]
groups, start = [], loud[0]
for a, b in zip(loud, loud[1:] + [None]):
    if b is None or b - a > 40: #(more than 0.4 s of quiet starts another group)
        groups.append((start, a))
        start = b
first, last = groups[0], groups[-1]
part_a = samples[max(0, first[0] * int(rate * 0.01) - int(0.03 * rate)):(first[1] + 6) * int(rate * 0.01)]
part_b = samples[max(0, last[0] * int(rate * 0.01) - int(0.03 * rate)):(last[1] + 6) * int(rate * 0.01)]
joined = fade_out(part_a, rate, 0.03) + [0.0] * int(0.18 * rate) + part_b
save("weapons/pistol_reload", "pistol_reload_01.wav", fade_out(joined, rate, 0.05), rate)

#ricochets: each starts where the sound jumps up after a quiet moment
samples, rate = read(os.path.join(DOWNLOADS, "854335__mikiko850__metal-bullet-ricochets.wav"))
env = envelope(samples, rate)
top = max(env)
onsets = []
for i, e in enumerate(env):
    if e > 0.3 * top and (not onsets or i - onsets[-1] > 60): #(a new ricochet: a loud start, not the tail of the last one)
        onsets.append(i)
step = int(rate * 0.01)
clean_folder("impacts/ricochet")
for n, at in enumerate(onsets):
    end = min(onsets[n + 1] if n + 1 < len(onsets) else len(env), at + 120) * step
    clip = trim(samples[max(0, at * step - int(0.01 * rate)):end], rate, threshold=0.04)
    if len(clip) > 0.08 * rate:
        save("impacts/ricochet", "ricochet_%02d.wav" % (n + 1), clip, rate)
