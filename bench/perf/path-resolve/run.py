import os,subprocess,json,statistics,sys,resource
os.sched_setaffinity(0, {int(os.environ.get('BENCH_CPU', '4'))})
rows=[]
for kind,n,reps in [('plain',0,100000),('plain',1,100000),('plain',4,40000),('plain',32,10000),('plain',256,1000),('plain',2048,30),('dots',4,20000),('dots',256,500),('absolute',256,1000),('invalid',256,10000),('windows',4,20000)]:
 samples=[]
 for i in range(int(os.environ.get('SAMPLES','21'))):
  row={}
  for name in (['base','new'] if i%2==0 else ['new','base']):
   p=subprocess.run([sys.argv[1]+'/'+name,kind,str(n),str(reps)],capture_output=True,text=True,check=True)
   ns,check=map(int,p.stdout.split());row[name]=ns/reps;row[name+'_checksum']=check
  assert row['base_checksum']==row['new_checksum']; samples.append(row)
 rows.append(dict(kind=kind,n=n,repeats=reps,samples=samples))
 print(kind,n,*(round(statistics.median(s[x] for s in samples),2) for x in ['base','new']),flush=True)
open(sys.argv[2],'w').write(json.dumps(rows,indent=2)+'\n')
