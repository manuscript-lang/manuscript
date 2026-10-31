import json, subprocess, statistics, pathlib, hashlib, platform, argparse, re, math
parser=argparse.ArgumentParser(description="Replay the ASCII decoder and unaffected controls, with alternating release processes")
parser.add_argument('--before',type=pathlib.Path,required=True)
parser.add_argument('--after',type=pathlib.Path,required=True)
parser.add_argument('--rust',type=pathlib.Path,required=True)
parser.add_argument('--output',type=pathlib.Path,required=True)
parser.add_argument('--repo',type=pathlib.Path,default=pathlib.Path(__file__).resolve().parents[3])
parser.add_argument('--ascii-only',action='store_true')
parser.add_argument('--baseline-revision')
args=parser.parse_args()
repo=args.repo.resolve()
out=args.output.resolve(); out.mkdir(parents=True,exist_ok=True)
binaries={v:getattr(args,v).resolve() for v in ['before','after','rust']}
files={'ascii':'encoding_ascii_bench.ms','regex':'regex_bench.ms','cardinality':'regex_cardinality_bench.ms','binary':'binary_bench.ms'}
if args.ascii_only: files={'ascii':files['ascii']}
expected_counts={'ascii':23,'regex':17,'cardinality':20,'binary':8}
expected_names={g:set(re.findall(r'^bench \"([^\"]+)\"', (repo/'bench/perf/stdlib'/f).read_text(),re.M)) for g,f in files.items()}
raw={v:{} for v in ['before','after','rust']}
identities={}
for group,file in files.items():
 for i in range(5):
  versions=['before','after'] if i%2==0 else ['after','before']
  if group=='ascii':
   if i%2==0: versions+=['rust']
   else: versions=['rust']+versions
  for v in versions:
   cmd=[str(binaries['rust'])] if v=='rust' else [str(binaries[v]),'bench',str(repo/'bench/perf/stdlib'/file),'--json','--samples','5' if group=='ascii' else '3','--time','100ms']
   r=subprocess.run(['taskset','-c','0',*cmd],capture_output=True,text=True,check=True)
   (out/f'{group}-{i}-{v}.json').write_text(r.stdout)
   (out/f'{group}-{i}-{v}.stderr').write_text(r.stderr)
   if v=='rust':
    parsed=[json.loads(line) for line in r.stdout.splitlines()]
    assert all(len(x['samples'])==5 and all(math.isfinite(v) and v>0 for v in x['samples']) for x in parsed),'Rust samples changed'
    rows={x['name']:statistics.median(x['samples']) for x in parsed}
    identity={name:1 for name in rows}
   else:
    d=json.loads(r.stdout)
    assert d['completed'] and d['exit_code']==0,d
    parsed=d['benches']
    assert all(x['status']=='passed' and x['stats']['samples']==(5 if group=='ascii' else 3) for x in parsed),d
    rows={x['name'].split('::')[-1]:x['stats']['median_ns'] for x in parsed}
    identity={x['name'].split('::')[-1]:x['stats']['operations'] for x in parsed}
   assert len(parsed)==len(rows),'duplicate names'
   assert len(rows)==expected_counts[group] and set(rows)==expected_names[group],(group,rows)
   if group not in identities: identities[group]=identity
   assert identity==identities[group],(v,group,identity,identities[group])
   for name,value in rows.items(): raw[v].setdefault(name,[]).append(value)
   print('completed',group,i,v,flush=True)
summary={}
for name in raw['before']:
 med={v:statistics.median(raw[v][name]) for v in raw if name in raw[v]}
 summary[name]={**med,'ratio':med['after']/med['before'],'distributions':{v:{'min':min(raw[v][name]),'max':max(raw[v][name]),'cv':statistics.pstdev(raw[v][name])/statistics.mean(raw[v][name])} for v in med}}
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
(out/'process-medians.json').write_text(json.dumps(raw,indent=2)+'\n')
(out/'identities.json').write_text(json.dumps(identities,indent=2)+'\n')
paths=[*binaries.values(),pathlib.Path(__file__).with_name('rust.rs'),repo/'stdlib/encoding.ms',*[repo/'bench/perf/stdlib'/f for f in files.values()]]
cpu_model=platform.processor() or platform.machine()
cpuinfo=pathlib.Path('/proc/cpuinfo')
if cpuinfo.is_file():
 cpu_model=next((line.split(':',1)[1].strip() for line in cpuinfo.read_text().splitlines() if line.startswith('model name')),cpu_model)
quota_path=pathlib.Path('/sys/fs/cgroup/cpu.max')
cpu_quota=quota_path.read_text().strip() if quota_path.is_file() else None
metadata={'baseline_revision':args.baseline_revision,'candidate_revision':subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),'platform':platform.platform(),'cpu':cpu_model,'cpu_affinity':'0','cpu_quota':cpu_quota,'rust':subprocess.check_output(['rustc','--version'],text=True).strip(),'hashes':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}}
(out/'environment.json').write_text(json.dumps(metadata,indent=2)+'\n')
print(json.dumps(summary,indent=2))
