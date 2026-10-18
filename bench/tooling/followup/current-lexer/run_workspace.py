#!/usr/bin/env python3
import argparse,hashlib,json,os,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--repo',required=True);p.add_argument('--label',required=True);p.add_argument('--modules',default='41,101');p.add_argument('--library',action='store_true');p.add_argument('--operations',default='symbols,references,rename');p.add_argument('--repeats',type=int,default=3);p.add_argument('--modes',default='counts,memory,latency');a=p.parse_args()
base=pathlib.Path(__file__).resolve().parent;old=base.parent/'selections';out=base/a.label;out.mkdir(parents=True,exist_ok=True);repo=pathlib.Path(a.repo).resolve()
subprocess.run(['python3',str(old/'prepare.py'),'--repo',str(repo),'--out',str(out)],check=True)
probeTarget=out/'pkg__tooling__lsp__followup_measurement_test.go';probeTarget.write_bytes((base/'workspace_probe_test.go.txt').read_bytes())
metadata=json.loads((out/'inputs.json').read_text());metadata['probe_sha256']=hashlib.sha256(probeTarget.read_bytes()).hexdigest();(out/'inputs.json').write_text(json.dumps(metadata,indent=2)+'\n')
countsOverlay=out/'overlay.json';overlay=json.loads(countsOverlay.read_text());plain={'Replace':{k:v for k,v in overlay['Replace'].items() if k.endswith('probe_hooks.go') or k.endswith('followup_measurement_test.go')}};(out/'plain-overlay.json').write_text(json.dumps(plain,indent=2)+'\n')
env={**os.environ,'GOCACHE':os.environ.get('GOCACHE','/tmp/manuscript-tooling-go-cache'),'GOMAXPROCS':'4','GOGC':'100','GOMEMLIMIT':'off','FOLLOWUP_PAYLOAD_DIR_ROOT':str(out/'payloads')}
for mode,overlayPath in [('counts',countsOverlay),('plain',out/'plain-overlay.json')]:
 with (out/f'build-{mode}.log').open('w') as log:subprocess.run([str(repo/'toolchain/go/bin/go'),'test','-c','-overlay='+str(overlayPath),'-o',str(out/f'probe-{mode}.test'),'./pkg/tooling/lsp'],cwd=repo,env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
records=[];lifecycle=[]
for modules in map(int,a.modules.split(',')):
 for operation in a.operations.split(','):
  for mode in a.modes.split(','):
   name=f'{"library" if a.library else "app"}-{modules}-{operation}-{mode}';runenv={**env,'FOLLOWUP_MODULES':str(modules),'FOLLOWUP_FUNCTIONS':'20','FOLLOWUP_OPERATION':operation,'FOLLOWUP_MODE':mode,'FOLLOWUP_REPEATS':str(a.repeats),'FOLLOWUP_LIBRARY':str(int(a.library))}
   done=subprocess.run([str(out/('probe-counts.test' if mode=='counts' else 'probe-plain.test')),'-test.run=^TestFollowupMeasurement$','-test.v','-test.timeout=10m'],cwd=repo,env=runenv,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);(out/(name+'.log')).write_text(done.stdout)
   if done.returncode:raise SystemExit('workspace probe failed '+name+': '+done.stdout[-2000:])
   for line in done.stdout.splitlines():
    if 'followup_measurement=' in line:records.append(json.loads(line.split('followup_measurement=',1)[1]))
    if 'followup_lifecycle=' in line:lifecycle.append(json.loads(line.split('followup_lifecycle=',1)[1]))
   print('passed '+name,flush=True)
(out/'measurements.json').write_text(json.dumps({'records':records,'lifecycle':lifecycle},indent=2)+'\n');print(out/'measurements.json')
