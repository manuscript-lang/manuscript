import hashlib,json,os,pathlib,platform,statistics,subprocess,sys
binaries=[pathlib.Path(x).resolve() for x in sys.argv[1:-1]]
out=pathlib.Path(sys.argv[-1])
report={'complete':False,'affinity':sorted(os.sched_getaffinity(0)),'platform':platform.platform(),'sha256':{str(b):hashlib.sha256(b.read_bytes()).hexdigest() for b in binaries},'cases':[]}
with out.open('x') as f:json.dump(report,f)
def trial(b,mode,n,repeats,pattern):
 left=set(range(n)) if pattern!='empty-left' else set()
 right=set(range(n))
 if pattern=='empty-right':right=set()
 if pattern=='disjoint':right=set(range(n,2*n))
 if pattern=='small-right':right={n} if n else set()
 if pattern in ('early','late') and n:
  right.remove(0 if pattern=='early' else n-1);right.add(n)
 expected={'subset':left<=right,'superset':left>=right,'disjoint':left.isdisjoint(right)}[mode]*repeats
 p=subprocess.run([str(b),mode,str(n),str(repeats),pattern],capture_output=True,text=True,timeout=90)
 if p.returncode or p.stderr or len(p.stdout.split())!=2:raise ValueError(repr(p))
 ns,checksum=map(int,p.stdout.split())
 if ns<=0 or checksum!=expected:raise ValueError((mode,n,pattern,ns,checksum,expected))
 return ns
for n,repeats in [(65536,1000000)]:
 for mode in ('subset','superset','disjoint'):
  for pattern in ('equal','disjoint','small-right','early','late'):
   if mode in ('subset','superset') and pattern not in ('disjoint','small-right','early'):
    continue
   if mode == 'disjoint' and pattern not in ('equal','early','late'):
    continue
   row={'mode':mode,'size':n,'repeats':repeats,'pattern':pattern,'samples':{str(b):[] for b in binaries}}
   for b in binaries:trial(b,mode,n,repeats,pattern)
   for sample in range(12):
    order=binaries[sample%len(binaries):]+binaries[:sample%len(binaries)]
    for b in order:row['samples'][str(b)].append(trial(b,mode,n,repeats,pattern))
   row['median_ns']={b:statistics.median(s) for b,s in row['samples'].items()}
   report['cases'].append(row);out.write_text(json.dumps(report,indent=2)+'\n')
   print(mode,n,pattern,row['median_ns'],flush=True)
report['complete']=True;out.write_text(json.dumps(report,indent=2)+'\n')
