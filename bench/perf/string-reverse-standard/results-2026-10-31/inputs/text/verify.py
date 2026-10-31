"""Untimed verification of compiled outputs and exact oracle identities."""
from pathlib import Path
import csv
import hashlib
import io
import json
import subprocess

ROOT = Path('/workspace/text-discovery')


def run(name, *arguments):
    result = subprocess.run([str(ROOT / name), *arguments], capture_output=True, text=True)
    assert result.returncode == 0 and not result.stderr, (name, result.returncode, result.stdout, result.stderr)
    return result.stdout


rust_verify = run('text-discovery-rust', '--verify')
assert rust_verify == 'verified 63 exact scalar-search/owned-split outputs\n'
(ROOT / 'rust-verify.log').write_text(rust_verify)
inventory = run('text-discovery-rust', '--inventory')
(ROOT / 'rust-inventory.csv').write_text(inventory)
rows = list(csv.DictReader(io.StringIO(inventory)))
actual = {row['case']: [int(row[key]) for key in ('input_bytes', 'iterations', 'checksum')] for row in rows}
expected = json.loads((ROOT / 'identities.json').read_text())
assert len(rows) == len(actual) == len(expected) == 63
assert list(actual) == list(expected) and actual == expected
ms_verify = run('text-discovery-ms-verify')
assert not ms_verify
(ROOT / 'ms-verify.stdout').write_text(ms_verify)
(ROOT / 'ms-verify.stderr').write_text('')

compiler = Path('/workspace/byte-search-evidence/fresh-main-988/ms-compiler')
archive = Path('/workspace/byte-search-evidence/fresh-main-988/baseline.a')
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
assert sha(compiler) == 'c0206ad63cab27353feb941a70d4f500dca2856beeb184e4cd98cf3b997a4a85'
source_tree = Path('/workspace/manuscript')
base_pin = subprocess.check_output(['git', '-C', str(source_tree), 'rev-parse', '98854115f'], text=True).strip()
record = {
    'source_tree_revision': '58691f4e3e9143c47ddc5801902e9aba8a8633ab',
    'baseline_main_revision': base_pin,
    'compiler': str(compiler), 'compiler_sha256': sha(compiler),
    'runtime_archive': str(archive), 'runtime_archive_sha256': sha(archive),
    'case_count': 63, 'split_cases': 18, 'search_cases': 45,
    'ms_untimed_companion_verified': True, 'rust_same_binary_verified': True,
    'rust_inventory_exact_oracle_match': True, 'timed_benchmarks_executed': False,
    'iteration_rule': 'min(100000,max(16,8388608//max(32,estimated_work_bytes)))',
    'rust_flags': ['--edition=2024', '-C', 'opt-level=3', '-C', 'overflow-checks=yes', '-C', 'force-frame-pointers=yes'],
    'ms_build_type': 'Release', 'ms_build_cache': str(ROOT / 'cache'),
    'source_contract_hashes': {name: sha(source_tree / name) for name in
                             ['crates/ms-rt/src/string.rs', 'stdlib/intrinsics.ms']},
    'artifacts': {str(path.relative_to(ROOT)): sha(path) for path in ROOT.iterdir()
                  if path.is_file() and path.name != 'build-and-verify.json'},
}
(ROOT / 'build-and-verify.json').write_text(json.dumps(record, indent=2) + '\n')
print('all 63 untimed MS companion/Rust outputs pass; Rust inventory exactly matches independent oracle; no timings')
