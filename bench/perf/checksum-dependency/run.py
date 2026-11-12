import os,sys,subprocess,json,zlib,statistics,hashlib
from pathlib import Path
p=Path(sys.argv[2]).resolve() if len(sys.argv)>2 else Path(__file__).parent
os.sched_setaffinity(0,{4})
mode=sys.argv[1] if len(sys.argv)>1 else 'base'
cases=[]
for alg in ['crc','adler']:
 for n in [0,1,7,8,9,15,16,17,64,256,1024,65535,65536,65537,1048576,1048577]: cases.append((alg,n,0,0 if alg=='crc' else 1))
 for n,chunk,seed in [(0,7,4294967295),(1,7,4294967295),(1024,7,0x12345678),(5552,5552,4294967295),(65536,4096,0x87654321)]:cases.append((alg,n,chunk,seed))
if mode=='aa': cases=[('crc',1,0,0),('adler',1,0,1),('crc',65536,0,0),('adler',65536,0,1)]
rows=[]
for alg,n,chunk,seed in cases:
 data=bytes((i*73+i//7+seed)%256 for i in range(n))
 initial=seed if chunk else (0 if alg=='crc' else 1)
 expected=initial if len(data)==0 else (zlib.crc32 if alg=='crc' else zlib.adler32)(data,initial)&0xffffffff
 count=max(20,min(1000000,50000000//max(n,1)))
 binaries={'ms':'ms','c':'c'} if mode=='base' else ({'ms':'ms','c':'ms-aa'} if mode=='aa' else {'ms':'ms','c':'new'})
 samples=[]
 for i in range(21):
  pair={}
  for side in (['ms','c'] if i%2==0 else ['c','ms']):
   result=subprocess.run([str(p/binaries[side]),alg,str(n),str(chunk),str(seed),str(count),str(expected)],capture_output=True,text=True,check=True)
   elapsed,checksum,got=map(int,result.stdout.split())
   assert got==expected and checksum==expected*count
   pair[side]=elapsed/count;pair[side+'_checksum']=checksum;pair[side+'_output']=got
  samples.append(pair)
 rows.append(dict(alg=alg,n=n,chunk=chunk,seed=seed,count=count,expected=expected,samples=samples))
 (p/(mode+'-samples.json')).write_text(json.dumps(rows,indent=2)+'\n')
 print(alg,n,chunk,seed,*[round(statistics.median(r[k] for r in samples),2) for k in ['ms','c']],flush=True)
(p/(mode+'-samples.json')).write_text(json.dumps(rows,indent=2)+'\n')
(p/(mode+'-metadata.json')).write_text(json.dumps(dict(baseline='5082ec904cfbe1f71f42e7cdbfc4b4e818c201e6',cpu=4,side_files=binaries,binaries={name:hashlib.sha256((p/file).read_bytes()).hexdigest() for name,file in binaries.items()},compiler_flags=('C -O3 -march=x86-64 -mtune=generic; MS LLVM Release' if mode=='base' else 'Both sides Manuscript LLVM Release; no C binary participates'),warmups=100,validation=('Every UInt32 and aggregate checked against zlib except documented empty Adler seed identity; C-only memory barrier prevents input hoisting' if mode=='base' else 'Both Manuscript complete UInt32 outputs and aggregates checked; no C barrier participates')),indent=2)+'\n')
