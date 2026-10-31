"""Copy immutable text evidence only; never execute benchmarks or publish binaries."""
from pathlib import Path
import hashlib
import json
import platform
import shutil
import subprocess

SOURCE = Path('/workspace/reverse-std-evidence')
REPO = Path('/workspace/reverse-std-perf')
DEST = REPO / 'bench/perf/string-reverse-standard/results-2026-10-31'
DEST.mkdir(parents=True, exist_ok=True)
origins = {}
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()


def copy(source, target):
    source, target = Path(source), DEST / target
    data = source.read_bytes()
    assert not data.startswith((b'\x7fELF', b'!<arch>')), str(source)
    assert source.suffix not in ('.a', '.ll', '.o', '.bc', '.pyc'), str(source)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
    origins[str(target.relative_to(DEST))] = {'original_path': str(source), 'sha256': sha(source)}


allowed = {'.json', '.csv', '.log', '.py', '.md', '.patch', '.txt', '.ms', '.rs', '.stdout', '.stderr'}
for source in sorted(SOURCE.rglob('*')):
    if not source.is_file() or source.suffix not in allowed or '__pycache__' in source.parts:
        continue
    relative = source.relative_to(SOURCE)
    if str(relative) == 'cc-version.log':
        # Retain this tool's trailing blank line losslessly without introducing
        # a whitespace-only diff failure in the evidence package.
        target = DEST / 'cc-version.log.json'
        target.write_text(json.dumps({'original_utf8': source.read_text(),
                                      'original_sha256': sha(source)}, indent=2) + '\n')
        origins[target.name] = {'original_path': str(source), 'sha256': sha(target),
                                'encoding': 'lossless-utf8-json', 'original_sha256': sha(source)}
        (DEST / 'cc-version.log').unlink(missing_ok=True)
        continue
    # Benchmark source is retained verbatim as text, outside formatter discovery.
    target = str(relative) + ('.txt' if source.suffix in ('.ms', '.rs') else '')
    copy(source, target)

states = json.loads((SOURCE / 'states.json').read_text())
for suite, entry in states['inputs'].items():
    path = Path(entry['path'])
    assert sha(path) == entry['sha256']
    copy(path, f'inputs/native/{suite}.ms.txt')

text_root = Path('/workspace/text-discovery')
for name in ('text-discovery.ms', 'text-discovery-verify.ms', 'text-discovery.rs', 'prepare.py',
             'verify.py', 'build.sh', 'identities.json', 'semantics.json', 'build-and-verify.json',
             'compaction-audit.json', 'SHA256SUMS', 'README.md'):
    copy(text_root / name, 'inputs/text/' + name + ('.txt' if name.endswith(('.ms', '.rs', '.sh')) else ''))

for preparation in ('initial-input-sized', 'pre-compaction'):
    directory = text_root / preparation
    for name in ('prepare.py', 'identities.json', 'build-and-verify.json', 'SHA256SUMS'):
        copy(directory / name, f'unmeasured-preparations/{preparation}/' + name)
    # Raw expected outputs are byte-identical to the one final semantics file.
    assert (directory / 'semantics.json').read_bytes() == (text_root / 'semantics.json').read_bytes()
    files = {path.name: sha(path) for path in directory.iterdir() if path.is_file()}
    target = DEST / f'unmeasured-preparations/{preparation}/original-files.json'
    target.write_text(json.dumps({'measured': False, 'files_sha256': files,
                                 'raw_semantics_identical_to': '../../inputs/text/semantics.json',
                                 'generated_sources_reconstructable_from': 'prepare.py',
                                 'binaries_published': False}, indent=2) + '\n')

reverse_root = Path('/workspace/reverse-discovery')
for name in ('reverse-control.rs', 'verify-inventory.py', 'build.sh', 'inventory.json',
             'content-identities.json', 'inventory-audit.json', 'rustc-version.txt', 'SHA256SUMS', 'README.md'):
    copy(reverse_root / name, 'inputs/reverse-rust/' + name + ('.txt' if name.endswith(('.rs', '.sh')) else ''))

byte_root = Path('/workspace/manuscript/bench/perf/bytes-index/rust')
for name in ('Cargo.toml', 'Cargo.lock', 'src/main.rs'):
    copy(byte_root / name, 'inputs/byte-rust/' + name + '.txt')
copy(REPO / 'bench/perf/representative/rss.c', 'inputs/rss-launcher.c.txt')

omitted = {}
for path in SOURCE.rglob('*'):
    if path.is_file() and path.suffix != '.pyc' and path.read_bytes()[:8].startswith((b'\x7fELF', b'!<arch>')):
        omitted[str(path.relative_to(SOURCE))] = sha(path)

cpu = next(line.split(':', 1)[1].strip() for line in Path('/proc/cpuinfo').read_text().splitlines()
           if line.startswith('model name'))
(DEST / 'host.json').write_text(json.dumps({'system': platform.platform(), 'cpu': cpu,
                                          'logical_cpus_exposed': 5, 'measurement_affinity': [0]}, indent=2) + '\n')
(DEST / 'publication-manifest.json').write_text(json.dumps({'text_artifacts': origins,
    'omitted_native_binaries_and_archives_sha256': omitted,
    'helper_ir_published': False, 'binary_files_published': False}, indent=2) + '\n')
print(f'copied {len(origins)} original text artifacts; excluded {len(omitted)} native binaries/archives')
