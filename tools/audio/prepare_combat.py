"""Makes the combat clips in game/audio/sounds from three recordings:
  python prepare_combat.py <pistol shot.wav> <bullet impacts.wav> <kill.wav> <sounds folder>
- weapons/pistol/pistol_01.wav            the shot
- impacts/wall/wall_01..N.wav             one clip per hit in the impacts recording (a bullet hitting a wall)
- kill/kill_01.wav                        the kill, as it is
- impacts/flesh/flesh_01..02.wav          a bullet hitting a body: the kill sound made shorter, duller, lower and much quieter
Every clip is mono 16 bit. The settings for the flesh hit are the constants below."""
import sys, wave, numpy as np

FLESH_LENGTH_S = (0.22, 0.28) #how long each flesh variation is: a fraction of the kill
FLESH_LOWPASS_HZ = (3000.0, 2200.0) #duller than the kill
FLESH_PITCH = (0.9, 0.82) #lower (a slower play-back)
FLESH_LEVEL = (0.9, 0.8) #peak level of the clip (the kill is 0.95)


def load(path):
    w = wave.open(path); sr, ch, sw = w.getframerate(), w.getnchannels(), w.getsampwidth()
    raw = w.readframes(w.getnframes())
    if sw == 3: #24 bit
        b = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3).astype(np.int32)
        v = b[:, 0] | (b[:, 1] << 8) | (b[:, 2] << 16)
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


def normalise(x, peak):
    return x * (peak / max(abs(x).max(), 1e-6))


def fade_out(x, seconds, sr):
    n = min(int(seconds * sr), len(x) // 2); x = x.copy(); x[-n:] *= np.linspace(1, 0, n) ** 2; return x


def lead_trim(x, sr, before=0.005):
    start = int(np.argmax(np.abs(x) > abs(x).max() * 0.08)); return x[max(0, start - int(before * sr)):]


def lowpass(x, sr, hz, order=2):
    pad = np.concatenate([x, np.zeros(int(0.1 * sr))]); f = np.fft.rfftfreq(len(pad), 1 / sr)
    return np.fft.irfft(np.fft.rfft(pad) / np.sqrt(1 + (f / hz) ** (2 * order)), len(pad))[:len(x)]


def repitch(x, factor): #factor under 1: lower and longer
    return np.interp(np.arange(0, len(x) - 1, factor), np.arange(len(x)), x)


shot_path, impacts_path, kill_path, out = sys.argv[1:5]

x, sr = load(shot_path)
save(out + "/weapons/pistol/pistol_01.wav", fade_out(normalise(lead_trim(x, sr), 0.95), 0.05, sr), sr)

x, sr = load(impacts_path)
hop = int(sr * 0.01)
env = np.array([np.sqrt((x[i:i + hop] ** 2).mean()) for i in range(0, len(x) - hop, hop)])
hits, last = [], -100
for i in range(1, len(env)):
    if env[i] > env.max() * 0.15 and env[i - 1] <= env.max() * 0.15 and i - last > 15:
        hits.append(i); last = i
for n, h in enumerate(hits):
    nxt = hits[n + 1] if n + 1 < len(hits) else len(env)
    seg = x[max(0, h * hop - int(0.01 * sr)):min(nxt * hop - int(0.03 * sr), h * hop + int(0.9 * sr))]
    e = np.array([np.sqrt((seg[i:i + hop] ** 2).mean()) for i in range(0, max(len(seg) - hop, 1), hop)])
    keep = np.where(e > e.max() * 0.004)[0]
    seg = seg[:max((keep[-1] + 2) * hop if len(keep) else len(seg), int(0.3 * sr))] #to where it has died away, at least 0.3 s
    save(out + "/impacts/wall/wall_%02d.wav" % (n + 1), fade_out(normalise(seg, 0.9), 0.06, sr), sr)

kill, sr = load(kill_path)
kill = lead_trim(kill, sr)
save(out + "/kill/kill_01.wav", fade_out(normalise(kill, 0.95), 0.08, sr), sr)

for n in range(2):
    seg = repitch(lowpass(kill, sr, FLESH_LOWPASS_HZ[n]), FLESH_PITCH[n])[:int(FLESH_LENGTH_S[n] * sr)]
    seg[:int(0.004 * sr)] *= np.linspace(0, 1, int(0.004 * sr)) #no click at the start
    save(out + "/impacts/flesh/flesh_%02d.wav" % (n + 1), fade_out(normalise(seg, FLESH_LEVEL[n]), 0.1, sr), sr)
