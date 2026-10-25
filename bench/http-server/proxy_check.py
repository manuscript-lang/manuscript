#!/usr/bin/env python3
"""Exercise proxy member distribution and reap the complete deployment on shutdown."""
import argparse,http.client,json,pathlib,subprocess,time
from soak import resources
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--proxy',required=True)
parser.add_argument('--server',required=True)
parser.add_argument('--port',type=int,default=19750)
parser.add_argument('--output',default='/tmp/http-proxy-smoke.json')
args=parser.parse_args()
child=subprocess.Popen([args.proxy,args.server,'4',f'127.0.0.1:{args.port}'])
try:
    for attempt in range(200):
        assert child.poll() is None, 'proxy exited during startup'
        connection=http.client.HTTPConnection('127.0.0.1',args.port,timeout=2)
        try:
            connection.request('GET','/'); response=connection.getresponse(); response.read()
            assert response.status==200
            break
        except OSError: time.sleep(.05)
        finally: connection.close()
    else: raise RuntimeError('proxy did not start')
    seen=set()
    connection=http.client.HTTPConnection('127.0.0.1',args.port,timeout=5)
    try:
        for _ in range(32):
            connection.request('GET','/cpu'); response=connection.getresponse(); response.read()
            assert response.status==200
            seen.add(response.getheader('X-Benchmark-Upstream'))
    finally: connection.close()
    assert seen=={'0','1','2','3'}, seen
    tree=resources(child.pid)
    assert len(tree)==5,tree
finally:
    child.terminate()
    try: child.wait(timeout=10)
    except subprocess.TimeoutExpired: child.kill();child.wait();raise
assert child.returncode==0, child.returncode
assert not any(pathlib.Path('/proc',str(p['pid'])).exists() for p in tree), tree
pathlib.Path(args.output).write_text(json.dumps({'requests':32,'upstreams':sorted(seen),'processes':len(tree),'normal_shutdown_exit':child.returncode,'all_processes_reaped':True},indent=2)+'\n')
