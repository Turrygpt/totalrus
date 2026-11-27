"""Prepare short hoof contacts from StephenSaldanha's CC0 horse foley.

Source: https://freesound.org/people/StephenSaldanha/sounds/165532/
Public HQ preview retained unchanged beside this script.
Processing uses the installed ffmpeg skill; originals are never overwritten.
"""
from array import array
import json
import math
from pathlib import Path
import subprocess
import sys
import wave

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SKILL = Path('C:/Users/Admin/.codex/skills/ffmpeg-skill/scripts')
SEGMENTS = [(2.410, 2.540), (2.890, 3.020), (3.370, 3.500),
            (3.845, 3.975), (6.260, 6.390), (7.240, 7.380),
            (7.700, 7.850), (8.650, 8.790)]


def run(tool, *args):
    command = [sys.executable, str(SKILL / (tool + '.py')), *map(str, args), '--json']
    proc = subprocess.run(command, capture_output=True, text=True, encoding='utf-8')
    if proc.returncode:
        raise RuntimeError(proc.stdout + proc.stderr)
    return json.loads(proc.stdout)


def stats(path):
    with wave.open(str(path), 'rb') as stream:
        rate = stream.getframerate()
        channels = stream.getnchannels()
        samples = array('h', stream.readframes(stream.getnframes()))
    peak = max(abs(x) for x in samples)
    rms = math.sqrt(sum(x*x for x in samples) / len(samples))
    return {'duration': len(samples) / rate / channels, 'sample_rate': rate,
            'channels': channels, 'peak_dbfs': 20*math.log10(peak/32768),
            'rms_dbfs': 20*math.log10(rms/32768),
            'clipped_samples': sum(abs(x) >= 32767 for x in samples)}


def main():
    reports = []
    for index, (start, end) in enumerate(SEGMENTS):
        cut = HERE / f'contact_{index:02d}.wav'
        destination = ROOT / 'assets/audio' / f'hoof_{index:02d}.wav'
        cut_args = [HERE / 'horse_mono.wav', '--start', start,
                    '--end', end, '--accurate', '-o', cut, '--overwrite']
        run('cut', *cut_args, '--dry-run')
        cut_report = run('cut', *cut_args)
        gain = -3.0 - stats(cut)['peak_dbfs']
        audio_args = [cut, '--mono', '--gain', f'{gain:.4f}',
                      '--fade-in', '.002', '--fade-out', '.018',
                      '-o', destination, '--overwrite']
        run('audio', *audio_args, '--dry-run')
        audio_report = run('audio', *audio_args)
        identity = audio_report['output_identity']
        check = run('check', destination, '--platform', 'custom',
                    '--max-duration', '.25', '--max-mb', '.1', '--no-loudness',
                    '--content', '--expect-identity',
                    f"{identity['size']}:{identity['mtime_ns']}")
        result = stats(destination)
        assert result['channels'] == 1 and result['clipped_samples'] == 0
        reports.append({'file': str(destination.relative_to(ROOT)),
                        'source_start': start, 'source_end': end, 'gain_db': gain,
                        'metrics': result, 'cut': cut_report, 'audio': audio_report,
                        'check': check})
        print(destination.name, json.dumps(result))
    (HERE / 'report.json').write_text(json.dumps(reports, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
