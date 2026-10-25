#!/usr/bin/env python3
"""Whole-handler CPU scaling with a separate low-overhead Go load client."""
import argparse
import asyncio
import hashlib
import json
import os
import pathlib
import platform
import signal
import subprocess
from scaling import cpu_ticks
from soak import request, resources


async def run(args):
    records = []
    metadata = {'platform': platform.platform(), 'cpu_max': pathlib.Path('/sys/fs/cgroup/cpu.max').read_text().strip(),
                'affinity': sorted(os.sched_getaffinity(0)), 'shared_runner': True, 'persistent_connections': 64,
                'server_sha256': hashlib.sha256(pathlib.Path(args.server).read_bytes()).hexdigest(),
                'client_sha256': hashlib.sha256(pathlib.Path(args.client).read_bytes()).hexdigest()}
    configurations = [(mode, count, args.server) for mode in ['workers', 'processes'] for count in [1, args.members]]
    if args.proxy:
        configurations.append(('proxy', args.members, args.proxy))
        metadata['proxy_sha256'] = hashlib.sha256(pathlib.Path(args.proxy).read_bytes()).hexdigest()
    for round_index in range(2):
        for mode, count, binary in configurations:
            with open(args.output + '.server.log', 'a') as log:
                server = subprocess.Popen([binary, args.server if mode == "proxy" else mode, str(count), f'127.0.0.1:{args.port}'], stdout=log, stderr=log)
                try:
                    for _ in range(200):
                        if server.poll() is not None: raise RuntimeError('server exited during startup')
                        try: await request(args.port, '/'); break
                        except Exception: await asyncio.sleep(.05)
                    else: raise RuntimeError('startup timeout')
                    command = [args.client, '-address', f'http://127.0.0.1:{args.port}/cpu', '-clients', '64']
                    subprocess.run(command + ['-duration', '1s'], stdout=subprocess.DEVNULL, check=True)
                    before = cpu_ticks(server.pid, True)
                    measurement = json.loads(subprocess.check_output(command + ['-duration', '8s'], text=True))
                    after = cpu_ticks(server.pid, True)
                    cores = {tid: (ticks-before.get(tid, ticks))/os.sysconf('SC_CLK_TCK')/measurement['load_seconds'] for tid,ticks in after.items()}
                    records.append({'round': round_index+1, 'mode': mode, 'member_count': count,
                                    'cpu_cores_by_thread': cores, 'resources': resources(server.pid), **measurement})
                    pathlib.Path(args.output).write_text(json.dumps({'metadata': metadata, 'records': records}, indent=2)+'\n')
                    print(json.dumps(records[-1]), flush=True)
                finally:
                    server.send_signal(signal.SIGTERM)
                    try: server.wait(timeout=10)
                    except subprocess.TimeoutExpired: server.kill(); server.wait()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server', required=True)
    parser.add_argument('--client', required=True)
    parser.add_argument('--proxy', help='Linux independent-server proxy benchmark binary')
    parser.add_argument('--members', type=int, default=4)
    parser.add_argument('--port', type=int, default=19747)
    parser.add_argument('--output', required=True)
    asyncio.run(run(parser.parse_args()))
