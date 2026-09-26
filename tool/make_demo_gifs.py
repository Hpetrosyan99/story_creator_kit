"""Turns docs/demo/*.mp4 into README GIFs: frames via tool/extract_frames.swift,
assembled with Pillow at 2x speed. Output: docs/demo/<name>.gif"""
import glob, os, shutil, subprocess, sys, tempfile
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FPS, SPEED, WIDTH = 8, 2.0, 300

for video in sorted(glob.glob(os.path.join(ROOT, 'docs/demo/*.mp4'))):
    name = os.path.splitext(os.path.basename(video))[0]
    tmp = tempfile.mkdtemp()
    # Sample at FPS*SPEED so the GIF plays SPEED times faster at FPS.
    subprocess.run(['swift', os.path.join(ROOT, 'tool/extract_frames.swift'),
                    video, tmp, str(FPS * SPEED), str(WIDTH)], check=True)
    frames = [Image.open(p).convert('RGB') for p in sorted(glob.glob(tmp + '/*.png'))]
    palette = frames[len(frames) // 2].quantize(colors=128, method=Image.Quantize.MEDIANCUT)
    quantized = [f.quantize(palette=palette, dither=Image.Dither.NONE) for f in frames]
    out = os.path.join(ROOT, 'docs/demo', name + '.gif')
    quantized[0].save(out, save_all=True, append_images=quantized[1:],
                      duration=int(1000 / FPS), loop=0, optimize=True)
    shutil.rmtree(tmp)
    print(name, len(frames), 'frames', os.path.getsize(out) // 1024, 'KB')
