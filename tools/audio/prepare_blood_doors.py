"""Makes the door and blood clips in game/audio/sounds:
  python prepare_blood_doors.py <door recording.wav> <splat recording.wav> <sounds folder>
- doors/open/door_open_01.wav, doors/close/door_close_01.wav   the recording's first and second door sound
- blood/splat_01..N.wav                                          every splat in the recording that is loud enough (SPLAT_MIN), one clip each
A recording that Godot cannot read (an .m4a) is first turned into a wav: python decode_to_wav.py in.m4a out.wav (needs the rig's venv: it uses Blender's audio)."""
import sys, wave, numpy as np

SPLAT_MIN = 0.3 #a splat has to peak at this share of the recording's loudest to be kept
SPLAT_MAX_S = 0.35 #and is cut to at most this long


def load(path):
    w = wave.open(path); sr, ch, sw = w.getframerate(), w.getnchannels(), w.getsampwidth()
    raw = w.readframes(w.getnframes())
    if sw == 3:
        b = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3).astype(np.int32); v = b[:, 0] | (b[:, 1] << 8) | (b[:, 2] << 16)
        v = np.where(v >= 1 << 23, v - (1 << 24), v).astype(np.float32) / (1 << 23)
    elif sw == 2:
        v = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768
    else:
        v = np.frombuffer(raw, dtype=np.int32).astype(np.float32) / 2 ** 31
    return v.reshape(-1, ch).mean(axis=1), sr


def save(path, x, sr):
    f = wave.open(path, "wb"); f.setnchannels(1); f.setsampwidth(2); f.setframerate(sr)
    f.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes()); f.close()
    print("%s  %.2fs" % (path.replace("\\", "/").split("/sounds/")[-1], len(x) / sr))


def finish(x, sr, peak, tail):
    x = x * (peak / max(abs(x).max(), 1e-6)); n = min(int(tail * sr), len(x) // 2); x[-n:] *= np.linspace(1, 0, n) ** 2
    x[:32] *= np.linspace(0, 1, 32); return x


def envelope(x, hop):
    return np.array([np.sqrt((x[i:i + hop] ** 2).mean()) for i in range(0, len(x) - hop, hop)])


def segments(env, share, min_hops, gap_hops):
    """runs of the envelope above `share` of its peak, runs closer than gap_hops joined: [(first hop, last hop)]"""
    runs, on = [], False
    for i, e in enumerate(env):
        if e > env.max() * share and not on: on = True; s = i
        if e <= env.max() * share and on:
            on = False; runs.append([s, i])
    if on: runs.append([s, len(env)])
    joined = []
    for r in runs:
        if joined and r[0] - joined[-1][1] <= gap_hops: joined[-1][1] = r[1]
        else: joined.append(r)
    return [(a, b) for a, b in joined if b - a >= min_hops]


door_path, splat_path, out = sys.argv[1:4]

x, sr = load(door_path); hop = int(sr * 0.01)
parts = segments(envelope(x, hop), 0.03, 20, 15) #the opening and the closing are the two long sounds
for name, (a, b) in zip(("door_open", "door_close"), parts[:2]):
    folder = "doors/open" if name == "door_open" else "doors/close"
    save("%s/%s/%s_01.wav" % (out, folder, name), finish(x[max(0, (a - 2) * hop):(b + 8) * hop], sr, 0.9, 0.12), sr)

x, sr = load(splat_path); hop = int(sr * 0.005)
env = envelope(x, hop)
hits = [(a, b) for a, b in segments(env, 0.02, 2, 3) if env[a:b].max() >= env.max() * SPLAT_MIN]
for n, (a, b) in enumerate(hits):
    nxt = hits[n + 1][0] if n + 1 < len(hits) else len(env)
    end = min(nxt * hop - int(0.02 * sr), a * hop + int(SPLAT_MAX_S * sr))
    seg = x[max(0, (a - 2) * hop):end]
    e = envelope(seg, hop); keep = np.where(e > e.max() * 0.03)[0]
    seg = seg[:max((keep[-1] + 3) * hop if len(keep) else len(seg), int(0.12 * sr))]
    save("%s/blood/splat_%02d.wav" % (out, n + 1), finish(seg, sr, 0.85, 0.06), sr)
