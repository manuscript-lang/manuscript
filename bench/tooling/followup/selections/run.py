#!/usr/bin/env python3
"""Build one instrumented test binary and execute isolated probe processes."""
import argparse,json,os,pathlib,subprocess,statistics
p=argparse.ArgumentParser();p.add_argument('--repo',default='/workspace/manuscript-tooling-followup');p.add_argument('--label',required=True);p.add_argument('--modules',default='41,101');p.add_argument('--operations',default='symbols,references,rename');p.add_argument('--modes',default='counts,memory');p.add_argument('--functions',type=int,default=20);p.add_argument('--repeats',type=int,default=3);p.add_argument('--library',action='store_true');p.add_argument('--no-build',action='store_true');a=p.parse_args()
base=pathlib.Path(__file__).resolve().parent;repo=pathlib.Path(a.repo).resolve();out=base/a.label;out.mkdir(parents=True,exist_ok=True)
env={**os.environ,'GOCACHE':os.environ.get('GOCACHE','/tmp/manuscript-tooling-go-cache'),'GOMAXPROCS':'4','GOGC':'100','GOMEMLIMIT':'off'}
if not a.no_build:
 subprocess.run(['python3',str(base/'prepare.py'),'--repo',str(repo),'--out',str(out)],check=True)
 with (out/'build.log').open('w') as log:subprocess.run([str(repo/'toolchain/go/bin/go'),'test','-c','-overlay='+str(out/'overlay.json'),'-o',str(out/'probe.test'),'./pkg/tooling/lsp'],cwd=repo,env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
records=[];lifecycle=[]
for modules in map(int,a.modules.split(',')):
 for operation in a.operations.split(','):
  for mode in a.modes.split(','):
   name=f'{"library" if a.library else "app"}-{modules}-{operation}-{mode}'
   runenv={**env,'FOLLOWUP_MODULES':str(modules),'FOLLOWUP_FUNCTIONS':str(a.functions),'FOLLOWUP_OPERATION':operation,'FOLLOWUP_MODE':mode,'FOLLOWUP_REPEATS':str(a.repeats),'FOLLOWUP_LIBRARY':str(int(a.library))}
   completed=subprocess.run([str(out/'probe.test'),'-test.run=^TestFollowupMeasurement$','-test.v','-test.timeout=10m'],cwd=repo,env=runenv,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
   (out/(name+'.log')).write_text(completed.stdout)
   if completed.returncode:raise SystemExit(f'probe failed {name}: see {out/(name+".log")}')
   for line in completed.stdout.splitlines():
    if 'followup_measurement=' in line:records.append(json.loads(line.split('followup_measurement=',1)[1]))
    if 'followup_lifecycle=' in line:lifecycle.append(json.loads(line.split('followup_lifecycle=',1)[1]))
   print(f'passed {name}',flush=True)
(out/'measurements.json').write_text(json.dumps({'records':records,'lifecycle':lifecycle},indent=2)+'\n')
summary=[]
for key in sorted({(r['modules'],r['operation'],r['mode'],r['library']) for r in records}):
 rows=[r for r in records if (r['modules'],r['operation'],r['mode'],r['library'])==key]
 item={'modules':key[0],'operation':key[1],'mode':key[2],'library':key[3],'samples':len(rows),'payload_counts':[r['payload_count'] for r in rows]}
 if key[2]=='counts':
  phases={}
  for phase in ['before','after']:
   phaseRows=[]
   for r in rows:
    sels=[s for s in r['selections'] if not s['recover'] and s['module'] and s['source_generation']==phase]
    phaseRows.append({'calls':sum(s['calls'] for s in sels),'unique':len(sels),'repeated_calls':sum(s['calls']-1 for s in sels)})
   phases[phase]=phaseRows
  item.update({'counters':[r['counts'] for r in rows],'strict_phases':phases})
 else:
  item.update({'median_elapsed_ms':statistics.median(r['elapsed_ns']/1e6 for r in rows),'peak_heap_deltas':[r['peak']['sampled_peak_heap_bytes']-r['before']['heap_bytes'] for r in rows],'peak_rss_deltas':[r['peak']['sampled_peak_rss_bytes']-r['before']['rss_bytes'] for r in rows],'postgc_heap_deltas':[r['after_gc']['heap_bytes']-r['before']['heap_bytes'] for r in rows],'sample_counts':[r['peak']['samples'] for r in rows]})
 summary.append(item)
(out/'summary.json').write_text(json.dumps({'summary':summary,'lifecycle':lifecycle},indent=2)+'\n')
print(out/'summary.json')
