#!/usr/bin/env python3
"""Validate and compare four already-built normalization states; never build them."""
import argparse
import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import statistics
import subprocess
import sys
from types import SimpleNamespace

LABELS = ('baseline', 'normalize_only', 'reverse_only', 'combined')
ROUNDS = 7
DEFAULT_PARSER = '/workspace/manuscript-strings-integrated/bench/perf/string-lines/compare.py'
DEFAULT_SOURCE = '/workspace/manuscript-strings-integrated/bench/perf/string-normalize-ascii/main.ms'


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f'duplicate JSON key: {key}')
        result[key] = value
    return result


def read_json(path):
    return json.loads(path.read_text(), object_pairs_hook=unique_object)


def write_json(path, value):
    with path.open('x') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')


def schedule():
    result = []
    for round_index in range(ROUNDS):
        rotation = round_index % len(LABELS)
        order = list(LABELS[rotation:] + LABELS[:rotation])
        if round_index // len(LABELS) % 2:
            order.reverse()
        result.append({'round': round_index, 'order': order})
    return result


def load_parser(path):
    spec = importlib.util.spec_from_file_location('factorial_shared_compare', path)
    module = importlib.util.module_from_spec(spec)
    previous_bytecode_policy = sys.dont_write_bytecode
    sys.dont_write_bytecode = True
    try:
        spec.loader.exec_module(module)
    finally:
        sys.dont_write_bytecode = previous_bytecode_policy
    if not callable(module.sample):
        raise ValueError('shared parser has no sample(executable, expected)')
    return module


def sample_with_output(parser, executable, expected):
    """Keep sample() unchanged; record its one subprocess invocation, including errors."""
    original_subprocess = parser.subprocess
    captured = {'returncode': None, 'stdout': '', 'stderr': ''}

    def recording_run(*args, **kwargs):
        try:
            result = original_subprocess.run(*args, **kwargs)
        except subprocess.CalledProcessError as error:
            captured.update(returncode=error.returncode, stdout=error.stdout or '',
                            stderr=error.stderr or '')
            raise
        captured.update(returncode=result.returncode, stdout=result.stdout or '',
                        stderr=result.stderr or '')
        return result

    # Replace only this imported module's subprocess binding, not sample() or the
    # process-wide subprocess.run. Its existing check=True/parser remains authoritative.
    parser.subprocess = SimpleNamespace(run=recording_run)
    try:
        return parser.sample(executable, expected), captured, None
    except BaseException as error:
        return None, captured, {'type': type(error).__name__, 'message': str(error)}
    finally:
        parser.subprocess = original_subprocess


def write_csv(path, fields, rows):
    with path.open('x', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, lineterminator='\n')
        writer.writeheader()
        writer.writerows(rows)


def normalized_summaries(samples, expected):
    values = {(row['round'], row['state'], row['case']):
              int(row['elapsed_ns']) / int(row['iterations']) for row in samples}
    summaries, paired_samples, paired_summary = [], [], []
    for state in LABELS:
        for name in expected:
            times = [values[r, state, name] for r in range(ROUNDS)]
            summaries.append({'state': state, 'case': name,
                              'median_ns': statistics.median(times),
                              'min_ns': min(times), 'max_ns': max(times)})
            if state == 'baseline':
                continue
            differences, ratios = [], []
            for r in range(ROUNDS):
                before, after = values[r, 'baseline', name], values[r, state, name]
                delta, ratio = after - before, before / after
                differences.append(delta)
                ratios.append(ratio)
                paired_samples.append({'round': r, 'state': state, 'case': name,
                                       'baseline_ns': before, 'state_ns': after,
                                       'after_minus_baseline_ns': delta,
                                       'baseline_div_state': ratio,
                                       'percent_change': (after / before - 1) * 100})
            paired_summary.append({'state': state, 'case': name,
                                   'faster_rounds': sum(d < 0 for d in differences),
                                   'equal_rounds': sum(d == 0 for d in differences),
                                   'slower_rounds': sum(d > 0 for d in differences),
                                   'paired_delta_median_ns': statistics.median(differences),
                                   'paired_delta_min_ns': min(differences),
                                   'paired_delta_max_ns': max(differences),
                                   'paired_speedup_median': statistics.median(ratios),
                                   'paired_speedup_min': min(ratios),
                                   'paired_speedup_max': max(ratios)})
    return summaries, paired_samples, paired_summary


def run(args):
    program_json, identity_json, parser_path, source = [Path(p).resolve(strict=True) for p in
        (args.programs, args.identity_file, args.parser, args.source)]
    programs = read_json(program_json)
    if not isinstance(programs, dict) or set(programs) != set(LABELS):
        raise ValueError(f'programs JSON must contain exactly {LABELS}')
    if any(not isinstance(value, str) or not value for value in programs.values()):
        raise ValueError('program paths must be nonempty strings')
    programs = {state: Path(programs[state]).resolve(strict=True) for state in LABELS}
    if len(set(programs.values())) != len(LABELS):
        raise ValueError('all four states require distinct resolved program paths')
    expected = read_json(identity_json)
    if not isinstance(expected, dict) or not expected:
        raise ValueError('identity JSON must be a nonempty object')
    for name, values in expected.items():
        if (not isinstance(name, str) or not name or not isinstance(values, list)
                or len(values) != 3 or any(type(n) is not int or n < 0 for n in values)
                or values[1] == 0):
            raise ValueError(f'invalid identity: {name}')
    expected = {name: tuple(values) for name, values in expected.items()}
    parser = load_parser(parser_path)
    run_dir = Path(args.output_dir).resolve() / args.prefix
    run_dir.mkdir(parents=True, exist_ok=False)  # Reserve once; never overwrite a prior run.
    (run_dir / 'producer-output').mkdir()
    protocol = {'format': 1, 'labels': LABELS, 'rounds': ROUNDS,
                'warmup_order': LABELS, 'round_schedule': schedule(),
                'schedule_rule': 'rotate labels left by round%4; reverse rounds4..6',
                'order_balance': 'near-balanced: each state appears1or2times per position, not fully balanced',
                'validation': 'unchanged shared sample(executable, expected), check=True',
                'summaries': 'only after all4warmups+28round producers validated and input hashes match',
                'pairing': 'same round vs baseline; no warmup pooling or state pooling',
                'scope': 'already-built producer operation timings, not launcher wall time'}
    write_json(run_dir / 'protocol.json', protocol)
    input_paths = {'orchestrator': Path(__file__).resolve(), 'shared_parser': parser_path,
                   'programs_json': program_json, 'identities_json': identity_json,
                   'benchmark_source': source, **{f'program:{s}': p for s, p in programs.items()}}
    before = {key: {'path': str(path), 'sha256': sha(path), 'size_bytes': path.stat().st_size}
              for key, path in input_paths.items()}
    write_json(run_dir / 'inputs.json', {'before': before, 'cases': len(expected),
               'protocol_sha256': sha(run_dir / 'protocol.json')})
    samples, validated, warmups = [], 0, 0
    active = None
    with (run_dir / 'raw-samples.csv').open('x', newline='') as raw_stream, \
            (run_dir / 'invocations.jsonl').open('x') as invocation_stream:
        writer = csv.DictWriter(raw_stream, fieldnames=['round', 'state', 'order_in_round',
            'case', 'input_bytes', 'iterations', 'elapsed_ns', 'checksum'], lineterminator='\n')
        writer.writeheader()
        raw_stream.flush()
        try:
            tasks = [('warmup', None, i, state) for i, state in enumerate(LABELS)]
            tasks += [('round', item['round'], i, state) for item in schedule()
                      for i, state in enumerate(item['order'])]
            for stage, round_index, position, state in tasks:
                invocation_id = f'warmup-{state}' if stage == 'warmup' else f'round{round_index}-{position}-{state}'
                active = {'id': invocation_id, 'stage': stage, 'round': round_index,
                          'state': state, 'order_in_round': position}
                rows, capture, error = sample_with_output(parser, str(programs[state]), expected)
                for stream_name in ('stdout', 'stderr'):
                    with (run_dir / 'producer-output' / f'{invocation_id}.{stream_name}').open('x') as stream:
                        stream.write(capture[stream_name])
                record = {**active, 'producer_returncode': capture['returncode'],
                          'validated': error is None, 'error': error,
                          'returncode_known': capture['returncode'] is not None,
                          'stdout': f'producer-output/{invocation_id}.stdout',
                          'stderr': f'producer-output/{invocation_id}.stderr'}
                invocation_stream.write(json.dumps(record) + '\n')
                invocation_stream.flush()
                if error is not None:
                    raise RuntimeError(f'{invocation_id}: {error["type"]}: {error["message"]}')
                validated += 1
                if stage == 'warmup':
                    warmups += 1
                    continue
                new_rows = [{'round': round_index, 'state': state,
                             'order_in_round': position, **row} for row in rows.values()]
                writer.writerows(new_rows)
                raw_stream.flush()
                samples.extend(new_rows)
            after = {key: {'path': str(path), 'sha256': sha(path), 'size_bytes': path.stat().st_size}
                     for key, path in input_paths.items()}
            unchanged = before == after
            write_json(run_dir / 'input-integrity.json', {'before': before, 'after': after,
                       'hashes_match': unchanged})
            if not unchanged:
                raise RuntimeError('protocol/input/program hash changed during run')
            assert validated == 32 and warmups == 4 and len(samples) == 28 * len(expected)
            summaries, paired_samples, paired_summary = normalized_summaries(samples, expected)
            for filename, result in [('state-summary.csv', summaries),
                                     ('paired-samples.csv', paired_samples),
                                     ('paired-summary.csv', paired_summary)]:
                write_csv(run_dir / filename, list(result[0]), result)
            write_json(run_dir / 'run-status.json', {'status': 'complete', 'validated_producers': validated,
                       'validated_warmups': warmups, 'validated_round_producers': validated - warmups,
                       'raw_rows': len(samples), 'cases': len(expected), 'rounds': ROUNDS,
                       'input_hashes_match': True, 'summaries_emitted': True})
        except BaseException as error:
            emitted_summaries = [name for name in ('state-summary.csv', 'paired-samples.csv',
                'paired-summary.csv') if (run_dir / name).exists()]
            failure = {'status': 'failed', 'active_invocation': active,
                       'error_type': type(error).__name__, 'error': str(error),
                       'validated_producers': validated, 'validated_warmups': warmups,
                       'raw_rows': len(samples), 'summaries_emitted': bool(emitted_summaries),
                       'summary_files': emitted_summaries,
                       'capture_limit': 'An interrupted/OSError invocation may have unknown returncode/output; see invocation record.'}
            write_json(run_dir / 'failure.json', failure)
            write_json(run_dir / 'run-status.json', failure)
            raise
    print(run_dir)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--programs', required=True, help='JSON object with exactly four fixed state paths')
    parser.add_argument('--identity-file', required=True)
    parser.add_argument('--output-dir', required=True)
    parser.add_argument('--prefix', required=True, help='new run subdirectory; never reused')
    parser.add_argument('--parser', default=DEFAULT_PARSER, help='existing shared compare.py path')
    parser.add_argument('--source', default=DEFAULT_SOURCE, help='unchanged source to hash; never executed here')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', args.prefix):
        parser.error('prefix must be a simple nonempty name beginning with a letter or digit')
    try:
        run(args)
    except BaseException as error:
        print(f'FAILED: {type(error).__name__}: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
