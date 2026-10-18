from pathlib import Path
import subprocess,statistics,json,random
cases=['list.fold','encoding.hex_encode','crypto.sha256','html.escape_unescape','queue.enqueue_dequeue'];samples={name:{'before':[],'after':[]} for name in cases};raw=[];expected={}
for i in range(15):
 order=cases[i%len(cases):]+cases[:i%len(cases)]
 for case in order:
  for version in (['before','after'] if i%2==0 else ['after','before']):
   out=subprocess.check_output(['/tmp/manuscript-focused-'+version,case],text=True,timeout=120)
   raw.append(version+' '+case+'\n'+out)
   rows=[line.split('\t') for line in out.splitlines() if not line.startswith('#')]
   sums=[line.split()[-1] for line in out.splitlines() if line.startswith('# checksum')]
   elapsed=[int(line.split()[-1]) for line in out.splitlines() if line.startswith('# elapsed')]
   assert len(elapsed)==20,(case,out)
   assert all(int(row[2])==ns//int(row[1]) for row,ns in zip(rows,elapsed))
   assert len(rows)==len(sums)==20,(case,out)
   identity=[(row[0],row[1],checksum) for row,checksum in zip(rows,sums)]
   assert all(x==identity[0] for x in identity)
   if case in expected:assert expected[case]==identity[0]
   else:expected[case]=identity[0]
   samples[case][version].append(statistics.median(ns/int(row[1]) for row,ns in zip(rows,elapsed)))
summary={case:{version:statistics.median(values) for version,values in pair.items()} for case,pair in samples.items()}
for case,pair in summary.items():pair['ratio']=pair['after']/pair['before']
Path('/tmp/manuscript-focused-results.txt').write_text(''.join(raw));Path('/tmp/manuscript-focused-summary.json').write_text(json.dumps({'summary':summary,'process_medians':samples,'identity':expected},indent=2))
print(json.dumps(summary,indent=2))
