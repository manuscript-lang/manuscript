"""Run only already-built native rotation binaries; preserve every sample."""
import hashlib, json, os, pathlib, platform, statistics, subprocess, sys

binary = str(pathlib.Path(sys.argv[1]).resolve())
cpu = min(os.sched_getaffinity(0))
env = dict(os.environ)
samples = []
subprocess.run([binary], check=True)
malformed = []
for w,h,count in [(0,0,0),(0,3,0),(-1,2,0),(2,-1,0),(2,2,15),(2,2,17),(2,2,20),(9223372036854775807,0,0),(0,9223372036854775807,0)]:
    for turn in (180,270):
        # The other extreme pair loops over Int.max empty rows in the baseline;
        # exercise only the pairs that reach its immediate overflow check.
        if w == 9223372036854775807 and turn == 270: continue
        if h == 9223372036854775807 and turn == 180: continue
        pair=[]
        for variant in ('base','direct'):
            p=subprocess.run([binary,'malformed',f'{variant}{turn}',str(w),str(h),str(count)],capture_output=True,text=True,timeout=10)
            pair.append(dict(status=p.returncode,stdout=p.stdout,stderr=p.stderr))
        assert pair[0]['status']==pair[1]['status'],pair
        assert pair[0]['stdout']==pair[1]['stdout'],pair
        if pair[0]['status']:
            assert pair[0]['stderr'].splitlines()[0]==pair[1]['stderr'].splitlines()[0],pair
        malformed.append(dict(width=w,height=h,count=count,turn=turn,results=pair))
for w, h, repeats, mode in [(1, 1, 10000,3), (3, 2, 10000,3), (64, 48, 200,3), (256, 192, 20,3), (1024, 768, 3,3), (64,48,200,0), (64,48,200,1), (64,48,200,2)]:
    for trial in range(7):
        kinds = ['base180','direct180','base270','direct270','control90']
        if trial % 2: kinds.reverse()
        checks = {}
        for kind in kinds:
            p = subprocess.run(['taskset', '-c', str(cpu), binary, kind, str(w), str(h), str(repeats),str(mode)],
                               capture_output=True, text=True, check=True, env=env)
            parts = p.stdout.strip().split()
            assert parts[:4] == [kind,str(w),str(h),str(repeats)], p.stdout
            ns, checksum = map(int, parts[4:])
            checks[kind] = checksum
            samples.append(dict(width=w,height=h,mode=mode,repeats=repeats,trial=trial,kind=kind,ns=ns,checksum=checksum,stdout=p.stdout,stderr=p.stderr))
        assert checks['base180'] == checks['direct180']
        assert checks['base270'] == checks['direct270']
    for turn in (180, 270):
        def median(kind):
            return statistics.median(s['ns']/s['repeats'] for s in samples
                if s['width']==w and s['height']==h and s['kind']==kind and s['mode']==mode)
        before, after = median(f'base{turn}'), median(f'direct{turn}')
        print(w,h,mode,turn, 'median_ns', round(before,2), round(after,2),'ratio',round(after/before,4), flush=True)
pathlib.Path(sys.argv[2]).write_text(json.dumps(dict(platform=platform.platform(),cpu=cpu,binary=binary,sha256=hashlib.sha256(pathlib.Path(binary).read_bytes()).hexdigest(),samples=samples,malformed=malformed), indent=2)+'\n')
