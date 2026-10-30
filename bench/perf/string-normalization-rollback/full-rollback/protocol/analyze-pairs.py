import csv,json,statistics as st,sys
from pathlib import Path
raw,manifest,prefix,pairs=sys.argv[1:];pairs=int(pairs)
rows=list(csv.DictReader(Path(raw).open()));expected=json.loads(Path(manifest).read_text()); grouped={name:{} for name in expected}
assert len(rows)==len(expected)*2*pairs
for r in rows:
 name=r['case']; pair=int(r['pair']);variant=r['variant'];assert name in expected and pair in range(pairs) and variant in ['before','after']
 assert [int(r[k]) for k in ['input_bytes','iterations','checksum']]==expected[name]
 entry=grouped[name].setdefault(pair,{});assert variant not in entry
 value=int(r['elapsed_ns'])/int(r['iterations']);assert value>0;entry[variant]=value
summary=[];per=[]
for name,data in grouped.items():
 assert set(data)==set(range(pairs))
 ds=[];ss=[]
 for i in range(pairs):
  assert set(data[i])=={'before','after'}
  b=data[i]['before'];a=data[i]['after'];d=a-b;s=b/a;ds.append(d);ss.append(s)
  per.append([name,i,b,a,d,s,100*(a/b-1)])
 summary.append([name,sum(d<0 for d in ds),sum(d==0 for d in ds),sum(d>0 for d in ds),st.median(ds),min(ds),max(ds),st.median(ss),min(ss),max(ss)])
for filename,header,data in [(prefix+'paired.csv',['case','faster_pairs','equal_pairs','slower_pairs','paired_delta_median_ns','paired_delta_min_ns','paired_delta_max_ns','paired_speedup_median','paired_speedup_min','paired_speedup_max'],summary),(prefix+'paired-samples.csv',['case','pair','before_ns','after_ns','after_minus_before_ns','before_div_after','percent_change'],per)]:
 with open(filename,'w',newline='') as f:
  w=csv.writer(f,lineterminator='\n');w.writerow(header)
  for row in data:w.writerow([f'{x:.9f}' if isinstance(x,float) else x for x in row])
print(len(expected),'cases',len(rows),'validated rows')
