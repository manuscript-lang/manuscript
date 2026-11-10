import csv,os,subprocess,statistics,resource
from pathlib import Path
binary='/workspace/lsp-query-tools/before/ms-lsp-query-perf'
out=Path('/workspace/manuscript/bench/perf/lsp-query/results-2026-11-10/discovery.csv')
cpu=min(os.sched_getaffinity(0))
with out.open('w') as f:
 w=csv.writer(f); w.writerow(['mode','count','rounds','shape','elapsed_ns','fingerprint','source_bytes','rss_kib','sample','minor_faults','major_faults'])
 for mode in ['hover-full-name-first','hover-full-name','hover-full','hover-full-symbol','symbols','completion']:
  for n in [1,100,1000,4000]:
   values=[]
   for sample in range(5):
    before=resource.getrusage(resource.RUSAGE_CHILDREN)
    p=subprocess.run(['taskset','-c',str(cpu),binary,mode,str(n),'10','ascii'],text=True,capture_output=True,check=True,timeout=90)
    after=resource.getrusage(resource.RUSAGE_CHILDREN)
    row=p.stdout.strip().split(','); w.writerow(row+[sample,after.ru_minflt-before.ru_minflt,after.ru_majflt-before.ru_majflt]);f.flush();values.append(int(row[4])/int(row[2])/1000)
   print(mode,n,round(statistics.median(values),3),'us',flush=True)
