"""Prepare the six CC0 Fantozzi sand/grass footsteps using the FFmpeg skill."""
from pathlib import Path
from array import array
import json
import math
import subprocess
import sys
import wave

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SKILL = Path('C:/Users/Admin/.codex/skills/ffmpeg-skill/scripts')
SOURCE = HERE / 'Fantozzi/Fantozzi-footsteps/flac'


def run(tool, args, log_name):
    result = subprocess.run([sys.executable, str(SKILL / tool), *map(str, args)],
                            capture_output=True, text=True, encoding='utf-8')
    (HERE / log_name).write_text(result.stdout + '\n' + result.stderr, encoding='utf-8')
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return json.loads(result.stdout)


def measure(path):
    with wave.open(str(path), 'rb') as wav:
        assert wav.getnchannels() == 1 and wav.getsampwidth() == 2
        rate = wav.getframerate()
        samples = array('h', wav.readframes(wav.getnframes()))
    peak = max(abs(v) for v in samples) / 32768.0
    rms = math.sqrt(sum(v*v for v in samples) / len(samples)) / 32768.0
    threshold = 32768 * 10 ** (-46 / 20)
    active = [i for i, value in enumerate(samples) if abs(value) > threshold]
    return {'duration_s': len(samples) / rate, 'sample_rate': rate,
            'channels': 1, 'peak_dbfs': 20 * math.log10(peak),
            'rms_dbfs': 20 * math.log10(rms),
            'leading_below_minus46_s': active[0] / rate,
            'trailing_below_minus46_s': (len(samples) - 1 - active[-1]) / rate,
            'clipped_samples': sum(abs(v) >= 32767 for v in samples)}


report = {'source_url': 'https://opengameart.org/content/fantozzis-footsteps-grasssand-stone',
          'download_url': 'https://opengameart.org/sites/default/files/Fantozzi-footsteps.7z',
          'author': 'Fantozzi; single-step edits uploaded by qubodup',
          'license': 'CC0 1.0', 'accessed': '2026-11-15',
          'notes': 'Sand clips are described by their publisher as suitable for grass. Original FLACs retained. No subjective listening assessment performed.',
          'clips': []}
for index, source in enumerate(sorted(SOURCE.glob('*Sand*.flac'))):
    analysis = HERE / f'sand_analysis_{index:02}.wav'
    if not analysis.exists():
        run('audio.py', [source, '-o', analysis, '--mono', '--dry-run', '--json'], f'analysis_{index:02}_plan.json')
        run('audio.py', [source, '-o', analysis, '--mono', '--json'], f'analysis_{index:02}_render.json')
    stats = measure(analysis)
    # Retain the original short decay; leave headroom for several nearby soldiers.
    gain = -4.0 - stats['peak_dbfs']
    output = ROOT / 'assets/audio' / f'boot_{index:02}.wav'
    args = [source, '-o', output, '--mono', '--gain', f'{gain:.4f}',
            '--fade-in', '.002', '--fade-out', '.018', '--overwrite']
    run('audio.py', [*args, '--dry-run', '--json'], f'boot_{index:02}_plan.json')
    result = run('audio.py', [*args, '--json'], f'boot_{index:02}_render.json')
    identity = result['output_identity']
    run('check.py', [output, '--platform', 'custom', '--max-duration', '.6', '--max-mb', '.1',
                     '--no-loudness', '--content', '--expect-identity',
                     f"{identity['size']}:{identity['mtime_ns']}", '--json'], f'boot_{index:02}_check.json')
    final = measure(output)
    assert final['clipped_samples'] == 0 and final['channels'] == 1
    report['clips'].append({'source': source.name, 'output': output.name, 'gain_db': gain, **final})
(HERE / 'report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps(report, indent=2))
