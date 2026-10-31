import csv,subprocess,statistics,math
from pathlib import Path
b=Path('/workspace/perf-evidence')
def run(binary,args):
 return subprocess.check_output(['taskset','--cpu-list','0',str(binary),*map(str,args)],text=True).strip().split(',')
with (b/'final-main-larger-flows.csv').open('w') as f:
 w=csv.writer(f,lineterminator='\n');w.writerow(['count','rounds','shape','elapsed_ns','fingerprint','source_bytes','output_bytes','peak_rss_kib','sample','cpu'])
 for n in [128,512,2048,4096]:
  for shape in ['flow','pipe']:
   ident=None
   for sample in range(5):
    r=run(b/'final-main-formatter-after',[n,5,shape]);assert len(r)==8
    if ident is None:ident=r[4:7]
    assert ident==r[4:7]
    w.writerow([*r,sample,0]);f.flush()
with (b/'final-main-workspace.csv').open('w') as f:
 w=csv.writer(f,lineterminator='\n');w.writerow(['modules','query','rounds','elapsed_ns','symbols','fingerprint','sample','cpu'])
 for n in [1,4,16,64]:
  for q in ['','only_target','missing']:
   ident=None
   for sample in range(5):
    r=run(b/'final-main-workspace-probe',[n,q,1]);assert len(r)==6
    if ident is None:ident=r[4:]
    assert ident==r[4:]
    w.writerow([*r,sample,0]);f.flush()
with (b/'final-main-new-candidates.csv').open('w') as f:
 w=csv.writer(f,lineterminator='\n');w.writerow(['mode','count','rounds','elapsed_ns','fingerprint','source_bytes','output_items_or_bytes','sample','cpu'])
 for mode,counts in [('completion',[1,128,512,2048]),('completion-doc',[1,128,512,2048]),('nesting',[1,8,32,64,128]),('calls',[1,8,32,128,512,2048])]:
  for n in counts:
   r=run(b/'final-main-discovery-probe',[mode,n,1]);assert len(r)==7
   ident=r[4:];rounds=min(10000,max(1,math.ceil(30e6/int(r[3]))))
   for sample in range(5):
    r=run(b/'final-main-discovery-probe',[mode,n,rounds]);assert len(r)==7 and r[4:]==ident
    w.writerow([*r,sample,0]);f.flush()
   print(mode,n,'done',flush=True)
