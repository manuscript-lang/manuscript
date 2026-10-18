#!/usr/bin/env python3
import hashlib,json,pathlib,re,statistics
root=pathlib.Path(__file__).resolve().parent
median=statistics.median
result={'index':[],'cold_balanced':[],'workspace':[],'payload_checks':[],'lifecycle':[]}
def read(p):return json.loads(p.read_text())
def compare(a,b):
 if a!=b:raise AssertionError('complete payload differs')
std=set();tokenhashes=set()
for shape,cases in [('app',['app-41','app-101']),('library',['library-11','library-21'])]:
 for case in cases:
  item={'case':case}
  payloads=[]
  for side in ['baseline','candidate']:
   directory=root/f'{side}-index-{shape}';cold=[r for r in read(directory/'cold.json') if r['case']==case];std.update(r['std_source_sha256'] for r in cold)
   warm=[list(map(int,row)) for row in re.findall(r'BenchmarkLexicalSourceIndex-\d+\s+\d+\s+(\d+) ns/op\s+(\d+) B/op\s+(\d+) allocs/op',(directory/(case+'-warm.log')).read_text())]
   item[side]={'warm_samples':warm,'warm_median_ns':median(r[0] for r in warm),'warm_median_bytes':median(r[1] for r in warm),'warm_median_allocations':median(r[2] for r in warm),'cold_samples':cold,'inventory':cold[0]['inventory']}
   first=(directory/'payloads'/case/'payload-0/source-index.json').read_bytes();second=(directory/'payloads'/case/'payload-1/source-index.json').read_bytes();compare(first,second);payloads.append(first)
   line=[line.split('lexical_tokens=',1)[1] for line in (directory/'token-inventory.log').read_text().splitlines() if 'lexical_tokens=' in line][0];tokenhashes.add(json.loads(line)['token_payload_sha256'])
  compare(*payloads)
  mutant=payloads[0].replace(b'"write":false',b'"write":true',1)
  assert mutant!=payloads[0]
  try:compare(mutant,payloads[1])
  except AssertionError:pass
  else:raise AssertionError('write mutant was accepted')
  result['payload_checks'].append({'case':case,'sha256':hashlib.sha256(payloads[0]).hexdigest(),'bytes':len(payloads[0]),'exact_byte_equal':True,'two_process_self_equal':True,'write_mutant_rejected':True})
  result['index'].append(item)
assert len(std)==1 and len(tokenhashes)==1,(std,tokenhashes)
result['std_source_sha256']=next(iter(std));result['token_payload_sha256']=next(iter(tokenhashes))
balanced=read(root/'balanced-cold/records.json')['records']
for n in [41,101]:
 row={'modules':n}
 for side in ['baseline','candidate']:
  rows=[r for r in balanced if r['modules']==n and r['side']==side];times=[r['elapsed_ns']/1e6 for r in rows]
  row[side]={'n':len(rows),'median_ms':median(times),'mean_ms':statistics.mean(times),'min_ms':min(times),'max_ms':max(times),'median_retained':median(r['retained_heap_delta'] for r in rows),'median_allocated':median(r['allocated_bytes'] for r in rows)}
 row['fixed_retained_difference']=row['candidate']['median_retained']-row['baseline']['median_retained'];result['cold_balanced'].append(row)
for shape in ['app','library']:
 b=read(root/f'baseline-workspace-{shape}/measurements.json');c=read(root/f'candidate-workspace-{shape}/measurements.json')
 for n in ([41,101] if shape=='app' else [11,21]):
  for op in ['symbols','references','rename']:
   item={'case':f'{shape}-{n}','operation':op}
   for mode in ['counts','memory','latency']:
    rows={side:[r for r in data['records'] if r['modules']==n and r['operation']==op and r['mode']==mode] for side,data in [('baseline',b),('candidate',c)]}
    assert all(len(v)==3 for v in rows.values())
    hashes={r['payload_sha256'] for rs in rows.values() for r in rs};assert len(hashes)==1,(shape,n,op,mode,hashes)
    for i in range(3):
     sub=f'{str(shape=="library").lower()}-{n}-{op}-{mode}/payload-{i}.json'
     compare((root/f'baseline-workspace-{shape}'/'payloads'/sub).read_bytes(),(root/f'candidate-workspace-{shape}'/'payloads'/sub).read_bytes())
    if mode=='counts':
     item['counts']={side:rs[0]['counts'] for side,rs in rows.items()};assert item['counts']['baseline']['strict_calls']==item['counts']['candidate']['strict_calls']
     for i in range(3):
      for phase in ['before','after']:
       counts=[]
       for side in ['baseline','candidate']:
        sels=[s for s in rows[side][i]['selections'] if not s['recover'] and s['module'] and s['source_generation']==phase];counts.append((sum(s['calls'] for s in sels),len(sels),sum(s['calls']-1 for s in sels)))
       assert counts[0]==counts[1]
    elif mode=='latency':item['latency']={side:{'samples_ms':[r['elapsed_ns']/1e6 for r in rs],'median_ms':median(r['elapsed_ns']/1e6 for r in rs)} for side,rs in rows.items()}
    else:item['memory']={side:[{'before_heap':r['before']['heap_bytes'],'absolute_peak_heap':r['peak']['sampled_peak_heap_bytes'],'before_rss':r['before']['rss_bytes'],'absolute_peak_rss':r['peak']['sampled_peak_rss_bytes'],'after_gc_heap':r['after_gc']['heap_bytes'],'samples':r['peak']['samples']} for r in rs] for side,rs in rows.items()}
   result['workspace'].append(item)
 for side,data in [('baseline',b),('candidate',c)]:
  for r in data['lifecycle']:
   if r['mode']=='memory':result['lifecycle'].append({'side':side,'case':f'{shape}-{r["modules"]}','operation':r['operation'],'baseline_heap':r['baseline']['heap_bytes'],'warm_open_heap':r['opened']['heap_bytes'],'closed_heap':r['closed']['heap_bytes'],'closed_minus_baseline':r['closed']['heap_bytes']-r['baseline']['heap_bytes'],'maps':[r['server_cache_uris'],r['server_analysis_entries'],r['server_indices'],r['server_lints']]})
(root/'summary.json').write_text(json.dumps(result,indent=2)+'\n')
print('all four full index payloads and all 108 workspace payload pairs byte-identical; write mutants rejected')
print(root/'summary.json')
