#!/usr/bin/env python3
"""Two-round, sequential baseline/member scaling measurements on the same host."""
import argparse
import asyncio
import json
import hashlib
import os
import pathlib
import platform
import signal
import subprocess
import time
from soak import load, request, resources


def cpu_ticks(pid, threads=False):
    result = {}
    for process in resources(pid):
        try:
            base = pathlib.Path(f'/proc/{process["pid"]}')
            paths = list((base / 'task').glob('*/stat')) if threads else [base / 'stat']
            for path in paths:
                fields = path.read_text().rsplit(')', 1)[1].split()
                identity = f"{process['pid']}:{path.parent.name}" if threads else str(process['pid'])
                result[identity] = int(fields[11]) + int(fields[12])
        except OSError:
            pass
    return result


async def run(args):
    rows = []
    metadata = {'platform': platform.platform(), 'affinity': sorted(os.sched_getaffinity(0)),
                'cpu_max': pathlib.Path('/sys/fs/cgroup/cpu.max').read_text().strip(),
                'build': 'Release', 'shared_runner': True,
                'server_sha256': hashlib.sha256(pathlib.Path(args.server).read_bytes()).hexdigest(),
                'baseline_sha256': hashlib.sha256(pathlib.Path(args.baseline).read_bytes()).hexdigest(),
                'baseline_commit': '0385da26a0bfcd3c891f332ba6883ed7c8372038',
                'baseline_reconstructed_after_implementation': True}
    configurations = [('baseline', 1, args.baseline), ('local', 1, args.server)]
    configurations += [(mode, count, args.server) for mode in ['workers', 'processes'] for count in sorted(set([1, 2, 4, args.members]))]
    if args.proxy:
        configurations.append(("proxy", args.members, args.proxy))
        metadata["proxy_sha256"] = hashlib.sha256(pathlib.Path(args.proxy).read_bytes()).hexdigest()
    for round_index in range(2):
        for mode, count, binary in configurations:
            with open(args.output + '.server.log', 'a') as log:
                child = subprocess.Popen([binary, args.server if mode == "proxy" else mode, str(count), f'127.0.0.1:{args.port}'], stdout=log, stderr=log)
                try:
                    for _ in range(200):
                        if child.poll() is not None: raise RuntimeError(f'{mode} startup failed')
                        try:
                            await request(args.port, '/')
                            break
                        except Exception: await asyncio.sleep(.05)
                    else: raise RuntimeError('startup timed out')
                    await load(args.port, 1, 8, '/cpu')
                    for path in ['/', '/cpu', '/slow']:
                        before = cpu_ticks(child.pid)
                        before_threads = cpu_ticks(child.pid, True)
                        start = time.monotonic()
                        measurement = await load(args.port, args.seconds, 32, path)
                        if mode == 'proxy':
                            measurement.pop('members', None)
                            measurement['member_distribution_note'] = 'Local backend bodies all report member 0; see persistent CPU probe upstream-header counts.'
                        elapsed = time.monotonic() - start
                        after = cpu_ticks(child.pid)
                        after_threads = cpu_ticks(child.pid, True)
                        cpu = {pid: (ticks-before.get(pid, ticks))/os.sysconf('SC_CLK_TCK')/elapsed for pid, ticks in after.items()}
                        rows.append({'round': round_index+1, 'mode': mode, 'member_count': count, 'path': path,
                                     'cpu_cores_by_process': cpu, 'cpu_cores_by_thread': {tid: (ticks-before_threads.get(tid, ticks))/os.sysconf('SC_CLK_TCK')/elapsed for tid, ticks in after_threads.items()}, 'resources': resources(child.pid), **measurement})
                        pathlib.Path(args.output).write_text(json.dumps({'metadata': metadata, 'records': rows}, indent=2)+'\n')
                        print(json.dumps({k: rows[-1][k] for k in ['round', 'mode', 'member_count', 'path', 'throughput', 'p99_ms', 'errors']}), flush=True)
                finally:
                    child.send_signal(signal.SIGTERM)
                    try: child.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        child.kill()
                        child.wait()
    return 0


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server', required=True)
    parser.add_argument('--baseline', required=True)
    parser.add_argument('--proxy', help='Linux independent-server proxy benchmark binary')
    parser.add_argument('--output', required=True)
    parser.add_argument('--members', type=int, default=4)
    parser.add_argument('--seconds', type=float, default=5)
    parser.add_argument('--port', type=int, default=19746)
    raise SystemExit(asyncio.run(run(parser.parse_args())))
