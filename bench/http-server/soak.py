#!/usr/bin/env python3
"""Bounded load/idle/recovery probe; records measurements, never invents pass thresholds."""
import argparse
import asyncio
import collections
import json
import hashlib
import os
import pathlib
import platform
import signal
import subprocess
import time


def descriptor_targets(base):
    result = collections.Counter()
    for descriptor in (base / 'fd').iterdir():
        try:
            target = os.readlink(descriptor)
            kind = target.split('[', 1)[0] if target.startswith(('socket:', 'pipe:', 'anon_inode:')) else target
            result[kind] += 1
        except OSError as error:
            result[type(error).__name__] += 1
    return dict(result)


def resources(root):
    pending, result = [root], []
    children_by_parent = collections.defaultdict(list)
    for entry in pathlib.Path('/proc').iterdir():
        if not entry.name.isdigit(): continue
        try:
            fields = dict(line.split(':', 1) for line in (entry / 'status').read_text().splitlines() if ':' in line)
            children_by_parent[int(fields['PPid'])].append(int(entry.name))
        except (OSError, KeyError, ValueError): pass
    while pending:
        pid = pending.pop()
        try:
            base = pathlib.Path('/proc') / str(pid)
            status = dict(line.split(':', 1) for line in (base / 'status').read_text().splitlines() if ':' in line)
            pending.extend(children_by_parent[pid])
            result.append({'pid': pid, 'rss_kib': int(status['VmRSS'].split()[0]),
                           'threads': int(status['Threads']), 'fds': len(list((base / 'fd').iterdir())), 'descriptor_targets': descriptor_targets(base)})
        except (OSError, KeyError, ValueError):
            pass
    return result


async def request(port, path):
    reader, writer = await asyncio.wait_for(asyncio.open_connection('127.0.0.1', port), 3)
    try:
        writer.write(f'GET {path} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n'.encode())
        await writer.drain()
        head = await asyncio.wait_for(reader.readuntil(b'\r\n\r\n'), 4)
        code = int(head.split(b' ', 2)[1])
        body = await asyncio.wait_for(reader.read(), 4)
        return code, body.decode(errors='replace')
    finally:
        writer.close()
        await writer.wait_closed()


async def load(port, seconds, concurrency, path):
    end = time.monotonic() + seconds
    codes, identities, errors = collections.Counter(), collections.Counter(), collections.Counter()
    latencies = collections.deque(maxlen=100000)
    error_samples = []
    async def client():
        while time.monotonic() < end:
            started = time.monotonic()
            try:
                code, body = await request(port, path)
                codes[code] += 1
                if code == 200:
                    identities[body.split(':', 1)[0].strip()] += 1
            except Exception as error:
                errors[type(error).__name__] += 1
                if len(error_samples) < 32:
                    error_samples.append({'type': type(error).__name__, 'at_unix': time.time(),
                                          'latency_ms': (time.monotonic()-started)*1000})
            latencies.append((time.monotonic() - started) * 1000)
    started = time.monotonic()
    await asyncio.gather(*(client() for _ in range(concurrency)))
    elapsed = time.monotonic() - started
    ordered = sorted(latencies)
    percentile = lambda q: ordered[min(len(ordered) - 1, int(len(ordered) * q))] if ordered else None
    return {'load_seconds': elapsed, 'statuses': dict(codes), 'errors': dict(errors), 'members': dict(identities),
            'error_samples': error_samples, 'throughput': sum(codes.values()) / elapsed, 'p50_ms': percentile(.5), 'p99_ms': percentile(.99)}


async def run(args):
    output = pathlib.Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    log = output.with_suffix('.server.log').open('w')
    server = subprocess.Popen([args.server, args.mode, str(args.members), f'127.0.0.1:{args.port}'], stdout=log, stderr=log)
    started = time.monotonic()
    records = []
    overload_clients = max(160, args.members * 96)
    metadata = {'platform': platform.platform(), 'cpu_count': os.cpu_count(), 'affinity': sorted(os.sched_getaffinity(0)),
                'mode': args.mode, 'members': args.members, 'duration': args.duration, 'pid': server.pid,
                'max_requests_per_member': 64, 'overload_clients': overload_clients,
                'binary_sha256': hashlib.sha256(pathlib.Path(args.server).read_bytes()).hexdigest(),
                'build': 'Release', 'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
                'working_tree': True, 'shared_runner': True}
    for path in ['/sys/fs/cgroup/cpu.max', '/sys/fs/cgroup/memory.max']:
        try: metadata[path] = pathlib.Path(path).read_text().strip()
        except OSError: pass
    try:
        for attempt in range(300):
            if server.poll() is not None: raise RuntimeError('server exited during startup')
            try:
                await request(args.port, '/')
                break
            except Exception: await asyncio.sleep(.1)
        else: raise RuntimeError('startup timeout')
        metadata['baseline'] = resources(server.pid)
        cycle = 0
        while time.monotonic() - started < args.duration:
            cycle += 1
            for phase, duration, concurrency, path in [('overload', 20, overload_clients, '/overload'), ('idle', 10, 0, '/'), ('recovery', 20, 16, '/'), ('idle', 10, 0, '/')]:
                if time.monotonic() - started >= args.duration: break
                if server.poll() is not None: raise RuntimeError('server exited during load')
                duration = min(duration, args.duration - (time.monotonic() - started))
                measurement = await load(args.port, duration, concurrency, path) if concurrency else {}
                if not concurrency: await asyncio.sleep(duration)
                row = {'cycle': cycle, 'phase': phase, 'elapsed': time.monotonic() - started,
                       'resources': resources(server.pid), **measurement}
                if not concurrency:
                    samples = {}
                    for _ in range(128):
                        try:
                            status, body = await request(args.port, '/stats')
                            if status == 200:
                                sample = json.loads(body)
                                samples[sample['member']] = sample
                            if len(samples) == args.members: break
                        except Exception as error:
                            row['sample_error'] = type(error).__name__
                            break
                    row['member_samples'] = samples
                records.append(row)
                output.write_text(json.dumps({'metadata': metadata, 'records': records}, indent=2) + '\n')
                print(json.dumps(row), flush=True)
    finally:
        server.send_signal(signal.SIGTERM)
        try: server.wait(timeout=10)
        except subprocess.TimeoutExpired:
            server.kill()
            server.wait()
        metadata['exit_code'] = server.returncode
        metadata['elapsed'] = time.monotonic() - started
        output.write_text(json.dumps({'metadata': metadata, 'records': records}, indent=2) + '\n')
        log.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--server', required=True)
    parser.add_argument('--mode', choices=['local', 'workers', 'processes'], default='processes')
    parser.add_argument('--members', type=int, default=4)
    parser.add_argument('--duration', type=float, default=1800)
    parser.add_argument('--port', type=int, default=19743)
    parser.add_argument('--output', required=True)
    asyncio.run(run(parser.parse_args()))
