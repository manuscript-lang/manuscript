#!/usr/bin/env python3
"""Check the reduced evidence package; omitted payloads require regeneration."""
import hashlib,json,pathlib
root=pathlib.Path(__file__).resolve().parent;summary=json.loads((root/'summary.json').read_text())
heads={'baseline':'b49c0c99a3bc89176ce7598fbc1c53c651bfe770','candidate':'9c2296984c92a2f90c08c1353775150802765bae'}
empty=hashlib.sha256(b'').hexdigest();records={};payloads={};cold_std=set();token_hashes=set()
for side in heads:
 for shape in ['app','library']:
  for kind in ['index','workspace']:
   directory=root/f'{side}-{kind}-{shape}';inputs=json.loads((directory/'inputs.json').read_text());assert inputs['head']==heads[side];assert inputs['working_diff_sha256']==empty
   probe='index_probe_test.go.txt' if kind=='index' else 'workspace_probe_test.go.txt';assert hashlib.sha256((root/probe).read_bytes()).hexdigest()==inputs['probe_sha256']
   for log in directory.glob('*.log'):
    for line in log.read_text().splitlines():
     if 'followup_measurement=' in line:
      r=json.loads(line.split('followup_measurement=',1)[1]);key=(shape,r['modules'],r['operation'],r['mode'],r['iteration']);records.setdefault(key,{})[side]=r
     if 'lexical_payload=' in line:
      r=json.loads(line.split('lexical_payload=',1)[1]);case=log.name.split('-payload-',1)[0];payloads.setdefault(case,[]).append(r)
     if 'lexical_cold=' in line:cold_std.add(json.loads(line.split('lexical_cold=',1)[1])['std_source_sha256'])
     if 'lexical_tokens=' in line:token_hashes.add(json.loads(line.split('lexical_tokens=',1)[1])['token_payload_sha256'])
assert len(records)==108,len(records)
for sides in records.values():
 assert set(sides)==set(heads)
 b,c=sides['baseline'],sides['candidate'];assert b['payload_sha256']==c['payload_sha256']
 if b['mode']=='counts':assert b['counts']['strict_calls']==c['counts']['strict_calls'] and c['counts']['standard_lex_calls']==0
for case,rows in payloads.items():
 expected=next(v for v in summary['payload_checks'] if v['case']==case);assert len(rows)==4
 assert all(r['payload_sha256']==expected['sha256'] and r['payload_bytes']==expected['bytes'] for r in rows)
assert cold_std=={summary['std_source_sha256']} and token_hashes=={summary['token_payload_sha256']}
assert all(x['maps']==[0,0,0,0] for x in summary['lifecycle'])
print('Verified exact heads/probe hashes, 108 recorded workspace payload pairs, four recorded full index payload pairs, standard digests, strict counts, cache cleanup. Omitted payload bytes were not regenerated.')
