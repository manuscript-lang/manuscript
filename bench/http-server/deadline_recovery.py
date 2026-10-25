#!/usr/bin/env python3
"""Identify resources retained after deadline cancellation, with child-owned proc access."""
import asyncio
import json
import pathlib
import signal
import sys
import subprocess
from soak import request,resources

async def main():
    child=subprocess.Popen([sys.argv[1] if len(sys.argv) > 1 else '/tmp/manuscript-http-bench-current','workers','4','127.0.0.1:19745'])
    observations=[]
    try:
        for _ in range(300):
            try: await request(19745,'/');break
            except OSError: await asyncio.sleep(.1)
        await asyncio.sleep(2)
        observations.append({'phase':'baseline','resources':resources(child.pid)})
        for cycle in range(3):
            responses=await asyncio.gather(*(request(19745,'/deadline') for _ in range(32)),return_exceptions=True)
            await asyncio.sleep(3)
            samples={}
            for _ in range(64):
                status,body=await request(19745,'/stats')
                if status==200:
                    value=json.loads(body);samples[value['member']]=value
                if len(samples)==4:break
            observations.append({'phase':'after-timeout','cycle':cycle,'responses':[str(x) if isinstance(x,Exception) else x[0] for x in responses],'resources':resources(child.pid),'samples':samples})
    finally:
        child.send_signal(signal.SIGTERM)
        try:child.wait(timeout=10)
        except subprocess.TimeoutExpired:child.kill();child.wait();raise
    pathlib.Path('/tmp/http-deadline-recovery.json').write_text(json.dumps(observations,indent=2)+'\n')
    print(json.dumps(observations),flush=True)
    counts = [sum(item['fds'] for item in row['resources']) for row in observations]
    assert len(set(counts)) == 1, counts
    samples = [row['samples'] for row in observations[1:]]
    assert all(len(sample) == 4 for sample in samples), samples
    for member in samples[0]:
        heaps = [sample[member]['heap_used'] for sample in samples]
        assert len(set(heaps)) == 1, (member, heaps)
        assert all(sample[member]['active_requests'] == 1 and sample[member]['active_connections'] == 1 for sample in samples)


asyncio.run(main())
