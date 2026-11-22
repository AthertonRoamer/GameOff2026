"""Cuts one long recording of footsteps into single soft steps: <out folder>/<prefix>_XX.wav (mono, 16 bit, 44.1 kHz).
Usage: python cut_steps.py <recording.wav> <out folder> [prefix]
A step is found by its sharp onset; the quick second hit of a heel-toe step stays with the step. Each is then softened (see SOFTEN): the clack of a hard
heel is filtered off, the spike of the strike is rounded, a little low thump is added and the ring is cut short, so it reads as a step on a floor, not a boot on stone."""
import sys, wave, numpy as np
SOFTEN = True
LOWPASS_HZ = 1800.0 #the clack lives above this; lower is duller
HIGHPASS_HZ = 70.0 #no rumble
SPIKE = 2.6 #soft limiting of the strike: higher rounds the peak more
ATTACK_S = 0.010 #how long the sound takes to come in (a hard heel is about 1 ms)
BODY_HZ = 220.0 #the low thump that is added...
BODY_MIX = 0.7 #...at this share of the step
STRIKE_AT_S = 0.03 #where in every clip the loudest point (the foot coming down) is placed
MAX_LENGTH_S = 0.30 #the ring is cut here
TAIL_S = 0.10 #and fades over this
src, out = sys.argv[1], sys.argv[2]
prefix = sys.argv[3] if len(sys.argv) > 3 else "stone"
w = wave.open(src); sr = w.getframerate()
d = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).reshape(-1, w.getnchannels()).astype(np.float32) / 32768
m = d.mean(axis=1)

def band(x, low=None, high=None, order=2):
    """zero-phase filter in the frequency domain: low passes below `low`, high passes above `high`"""
    spec = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1.0 / sr); g = np.ones_like(f)
    if low: g /= np.sqrt(1 + (f / low) ** (2 * order))
    if high: g *= 1 - 1 / np.sqrt(1 + (f / high) ** (2 * order))
    return np.fft.irfft(spec * g, len(x))

def centroid(x):
    s = np.abs(np.fft.rfft(x)); f = np.fft.rfftfreq(len(x), 1.0 / sr); return (s * f).sum() / s.sum()

hop = int(sr * 0.005)
env = np.array([np.sqrt((m[i:i + hop] ** 2).mean()) for i in range(0, len(m) - hop, hop)])
thr = max(env.max() * 0.18, np.percentile(env, 60) * 2)
onsets, last = [], -1000
for i in range(1, len(env)):
    if env[i] > thr and env[i - 1] <= thr and i - last > 25:
        onsets.append(i); last = i
steps = [o for k, o in enumerate(onsets) if k == 0 or (o - onsets[k - 1]) * 0.005 > 0.5] #a hit within half a second of the last belongs to the same step
for n, o in enumerate(steps):
    nxt = steps[n + 1] if n + 1 < len(steps) else len(env)
    a = max(0, int((o * hop) - 0.02 * sr))
    b = min(int(nxt * hop - 0.03 * sr), int(o * hop + (MAX_LENGTH_S if SOFTEN else 0.7) * sr + 0.02 * sr))
    seg = m[a:b].copy()
    before = centroid(seg)
    if SOFTEN:
        pad = np.concatenate([seg, np.zeros(int(0.2 * sr))]) #room for the filters' ringing
        dull = band(pad, low=LOWPASS_HZ, high=HIGHPASS_HZ)
        body = band(pad, low=BODY_HZ, high=HIGHPASS_HZ)
        mixed = dull + body * BODY_MIX
        mixed /= max(abs(mixed).max(), 1e-6)
        mixed = np.tanh(SPIKE * mixed) / np.tanh(SPIKE) #rounds the spike of the strike
        seg = mixed[:len(seg)]
        seg[:int(ATTACK_S * sr)] *= np.linspace(0, 1, int(ATTACK_S * sr)) ** 1.5
    shift = int(np.argmax(np.abs(seg))) - int(STRIKE_AT_S * sr) #every clip's strike lands at the same moment, so steps keep the beat the game gives them
    seg = seg[shift:] if shift > 0 else np.concatenate([np.zeros(-shift), seg])
    e = np.array([np.sqrt((seg[i:i + hop] ** 2).mean()) for i in range(0, max(len(seg) - hop, 1), hop)])
    keep = np.where(e > e.max() * 0.02)[0]
    end = min(len(seg), (keep[-1] + 2) * hop + int(0.04 * sr)) if len(keep) else len(seg)
    seg = seg[:max(end, int(0.15 * sr))]
    fade = min(int((TAIL_S if SOFTEN else 0.04) * sr), len(seg) // 2)
    seg[-fade:] *= np.linspace(1, 0, fade) ** 2 #the end fades out
    seg[:48] *= np.linspace(0, 1, 48) #and a hair of fade in, so a cut never clicks
    seg *= 0.7 / max(abs(seg).max(), 1e-6) #the same peak for every step, so the game sets the loudness
    pcm = (np.clip(seg, -1, 1) * 32767).astype(np.int16)
    f = wave.open("%s/%s_%02d.wav" % (out, prefix, n + 1), "wb")
    f.setnchannels(1); f.setsampwidth(2); f.setframerate(sr); f.writeframes(pcm.tobytes()); f.close()
    print("%s_%02d  %.2fs long  brightness %d Hz -> %d Hz" % (prefix, n + 1, len(seg) / sr, before, centroid(seg)))
