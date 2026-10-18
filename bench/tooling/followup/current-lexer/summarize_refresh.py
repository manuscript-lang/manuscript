#!/usr/bin/env python3
import hashlib,json,pathlib,re,statistics
root=pathlib.Path(__file__).resolve().parent;median=statistics.median
heads={'baseline':'55228347c8555186ab6a483459e161e1bef82326','candidate':'3232c8db008fe60804f88bb8a243d15ce8da0a14'}
result={'heads':heads,'index':[],'symbols':[],'payload_checks':[],'metadata':{}}
std=set();tokenhash=set()
for side in heads:
 for kind in ['index','workspace']:
  inputs=json.loads((root/f'{side}-{kind}-app/inputs.json').read_text());assert inputs['head']==heads[side];assert inputs['working_diff_sha256']==hashlib.sha256(b'').hexdigest();result['metadata'][side+'-'+kind]=inputs
for n in [41,101]:
 case=f'app-{n}';row={'case':case};payloads=[]
 for side in heads:
  directory=root/f'{side}-index-app';cold=[r for r in json.loads((directory/'cold.json').read_text()) if r['case']==case];std.update(r['std_source_sha256'] for r in cold)
  warm=[list(map(int,r)) for r in re.findall(r'BenchmarkLexicalSourceIndex-\d+\s+\d+\s+(\d+) ns/op\s+(\d+) B/op\s+(\d+) allocs/op',(directory/f'{case}-warm.log').read_text())]
  assert len(cold)==5 and len(warm)==3
  row[side]={'warm_samples':warm,'warm_median_ns':median(r[0] for r in warm),'warm_median_bytes':median(r[1] for r in warm),'warm_median_allocations':median(r[2] for r in warm),'cold_samples':cold,'cold_median_ms':median(r['elapsed_ns']/1e6 for r in cold),'cold_range_ms':[min(r['elapsed_ns']/1e6 for r in cold),max(r['elapsed_ns']/1e6 for r in cold)],'cold_median_bytes':median(r['allocated_bytes'] for r in cold),'retained_median_bytes':median(r['retained_heap_delta'] for r in cold),'inventory':cold[0]['inventory']}
  a=(directory/'payloads'/case/'payload-0/source-index.json').read_bytes();b=(directory/'payloads'/case/'payload-1/source-index.json').read_bytes();assert a==b;payloads.append(a)
  for line in (directory/'token-inventory.log').read_text().splitlines():
   if 'lexical_tokens=' in line:tokenhash.add(json.loads(line.split('lexical_tokens=',1)[1])['token_payload_sha256'])
 assert payloads[0]==payloads[1]
 mutant=payloads[0].replace(b'"write":false',b'"write":true',1);assert mutant!=payloads[0] and mutant!=payloads[1]
 result['payload_checks'].append({'case':case,'occurrences':row['baseline']['cold_samples'][0]['occurrences'],'bytes':len(payloads[0]),'sha256':hashlib.sha256(payloads[0]).hexdigest(),'byte_equal':True,'two_fresh_self_equal':True,'write_mutant_rejected':True})
 row['fixed_retained_difference']=row['candidate']['retained_median_bytes']-row['baseline']['retained_median_bytes'];result['index'].append(row)
 b=json.loads((root/'baseline-workspace-app/measurements.json').read_text())['records'];c=json.loads((root/'candidate-workspace-app/measurements.json').read_text())['records'];workspace={'case':case}
 for mode in ['counts','latency']:
  rows={side:[r for r in data if r['modules']==n and r['mode']==mode] for side,data in [('baseline',b),('candidate',c)]};assert all(len(v)==3 for v in rows.values());assert len({r['payload_sha256'] for rr in rows.values() for r in rr})==1
  for i in range(3):
   p=f'false-{n}-symbols-{mode}/payload-{i}.json';assert (root/'baseline-workspace-app/payloads'/p).read_bytes()==(root/'candidate-workspace-app/payloads'/p).read_bytes()
  if mode=='counts':
   workspace['counts']={side:rows[side][0]['counts'] for side in heads};assert workspace['counts']['baseline']['strict_calls']==workspace['counts']['candidate']['strict_calls'];assert workspace['counts']['candidate']['standard_lex_calls']==0
  else:workspace['latency']={side:{'samples_ms':[r['elapsed_ns']/1e6 for r in rr],'median_ms':median(r['elapsed_ns']/1e6 for r in rr)} for side,rr in rows.items()}
 result['symbols'].append(workspace)
assert len(std)==1 and len(tokenhash)==1;result['std_source_sha256']=next(iter(std));result['token_payload_sha256']=next(iter(tokenhash));assert result['metadata']['baseline-index']['source_sha256']['pkg/lexer/lexer.go']==result['metadata']['candidate-index']['source_sha256']['pkg/lexer/lexer.go']
(root/'summary.json').write_text(json.dumps(result,indent=2)+'\n');print('Two completeInfo payload pairs and12complete symbols payload pairs byteequal; fixedcounts/stdhashes verified.');print(root/'summary.json')
