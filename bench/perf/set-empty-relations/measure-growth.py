import hashlib,json,os,pathlib,platform,statistics,subprocess,sys
binaries=[pathlib.Path(x).resolve() for x in sys.argv[1:-1]];out=pathlib.Path(sys.argv[-1])
report={'complete':False,'platform':platform.platform(),'affinity':sorted(os.sched_getaffinity(0)),'sha256':{str(b):hashlib.sha256(b.read_bytes()).hexdigest() for b in binaries},'cases':[]}
with out.open('x') as f:json.dump(report,f)
def trial(b,mode,n,repeats,width):
 p=subprocess.run([str(b),mode,str(n),str(repeats),'a'*width],capture_output=True,text=True,timeout=120)
 if p.returncode or p.stderr or len(p.stdout.split())!=2:raise ValueError(repr(p))
 ns,checksum=map(int,p.stdout.split())
 if ns<=0 or checksum!=n*(n-1)*repeats:raise ValueError((b,mode,n,width,ns,checksum))
 return ns
for n,count in [(0,1000000),(1,100000),(8,20000),(128,2000),(4096,100),(65536,5)]:
 for mode in ('int_insert','int_churn','string_insert'):
  for width in ([0] if mode.startswith('int') else [0,16,256]+([4096] if n in (128,4096) else [])):
   repeats=max(1,count//(1+width//32))
   row={'mode':mode,'size':n,'prefix_width':width,'repeats':repeats,'samples':{str(b):[] for b in binaries}}
   for b in binaries:trial(b,mode,n,repeats,width)
   for sample in range(6):
    order=binaries[sample%len(binaries):]+binaries[:sample%len(binaries)]
    for b in order:row['samples'][str(b)].append(trial(b,mode,n,repeats,width))
   row['median_ns']={b:statistics.median(s) for b,s in row['samples'].items()}
   report['cases'].append(row);out.write_text(json.dumps(report,indent=2)+'\n')
   print(mode,n,width,row['median_ns'],flush=True)
report['complete']=True;out.write_text(json.dumps(report,indent=2)+'\n')
