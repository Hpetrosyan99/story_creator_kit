"""Turns docs/demo/*.mp4 into README GIFs: frames via tool/extract_frames.swift,
assembled with Pillow. Output: docs/demo/<name>.gif

One 256-colour palette per video, built from frames sampled across the whole
recording, so every scene keeps its real colours and static areas stay
identical between frames (small files, no flicker)."""
import glob, os, shutil, subprocess, sys, tempfile
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FPS, SPEED, WIDTH = 12, 1.5, 420
PALETTE_SAMPLES = 36
NOISE = 10


def stabilise(frames):
    """Copies pixels that changed by less than NOISE from the previous output
    frame, so encoder noise does not repaint static areas."""
    prev = np.asarray(frames[0]).astype(np.int16)
    out = [frames[0]]
    for f in frames[1:]:
        cur = np.asarray(f).astype(np.int16)
        same = np.abs(cur - prev).max(axis=2) < NOISE
        cur[same] = prev[same]
        prev = cur
        out.append(Image.fromarray(cur.astype(np.uint8)))
    return out


def palette_for(frames):
    step = max(1, len(frames) // PALETTE_SAMPLES)
    samples = frames[::step]
    w, h = samples[0].size
    thumb = (w // 2, h // 2)
    cols = 6
    rows = (len(samples) + cols - 1) // cols
    sheet = Image.new('RGB', (thumb[0] * cols, thumb[1] * rows))
    for i, f in enumerate(samples):
        sheet.paste(f.resize(thumb, Image.LANCZOS),
                    ((i % cols) * thumb[0], (i // cols) * thumb[1]))
    return sheet.quantize(colors=256, method=Image.Quantize.MEDIANCUT)


videos = sys.argv[1:] or sorted(glob.glob(os.path.join(ROOT, 'docs/demo/*.mp4')))
for video in videos:
    name = os.path.splitext(os.path.basename(video))[0]
    tmp = tempfile.mkdtemp()
    subprocess.run(['swift', os.path.join(ROOT, 'tool/extract_frames.swift'),
                    video, tmp, str(FPS * SPEED), str(WIDTH)],
                   check=True, stderr=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
    frames = [Image.open(p).convert('RGB') for p in sorted(glob.glob(tmp + '/*.png'))]
    frames = stabilise(frames)
    palette = palette_for(frames)
    quantized = [f.quantize(palette=palette, dither=Image.Dither.NONE) for f in frames]
    out = os.path.join(ROOT, 'docs/demo', name + '.gif')
    quantized[0].save(out, save_all=True, append_images=quantized[1:],
                      duration=round(1000 / FPS), loop=0, optimize=False)
    shutil.rmtree(tmp)
    print(name, len(frames), 'frames', os.path.getsize(out) // 1024, 'KB')
