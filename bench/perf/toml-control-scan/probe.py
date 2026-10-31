"""Check that cached-file producers detect changed input after setup."""
import argparse
import hashlib
import json
import os
import pathlib
import subprocess
import tempfile
import time

p = argparse.ArgumentParser()
p.add_argument('--before', type=pathlib.Path, required=True)
p.add_argument('--after', type=pathlib.Path, required=True)
p.add_argument('--output', type=pathlib.Path, required=True)
a = p.parse_args()
rows = []
for label,binary in [('before', a.before.resolve()), ('after', a.after.resolve())]:
    with tempfile.TemporaryDirectory(prefix='toml-observe-', dir=a.output.parent) as temp:
        root = pathlib.Path(temp)
        source, marker = root/'input.toml', root/'ready'
        source.write_text('value = "Ada"\n')
        process = subprocess.Popen([binary, source, '1000000', marker], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic()+5
            while not marker.exists() and process.poll() is None and time.monotonic()<deadline:
                time.sleep(0.005)
            if not marker.exists():
                raise ValueError('producer did not signal setup readiness')
            replacement = root/'replacement.toml'
            replacement.write_text('value = "Bob"\n')
            os.replace(replacement, source)
            out, err = process.communicate(timeout=5)
            if process.returncode != 1 or out or err:
                raise ValueError(f'producer failed to reject changed input: {process.returncode}, {out!r}, {err!r}')
            rows.append({'label': label, 'binary': str(binary), 'sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
                         'exit': process.returncode, 'result': 'changed external input rejected after setup'})
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()
a.output.write_text(json.dumps({'driver_sha256':hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(), 'records':rows}, indent=2)+'\n')
print('Both producers reject changed input after setup')
