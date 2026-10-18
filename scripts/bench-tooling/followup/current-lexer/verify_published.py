#!/usr/bin/env python3
"""Validate reduced recorded evidence, without recreating omitted payloads."""
import hashlib,json,pathlib
root=pathlib.Path(__file__).resolve().parent;s=json.loads((root/'summary.json').read_text());rows={};payloads={};std=set();tokens=set()
for side,head in s['heads'].items():
 for kind in ['index','workspace']:
  d=root/f'{side}-{kind}-app';inputs=json.loads((d/'inputs.json').read_text());assert inputs['head']==head and inputs['working_diff_sha256']==hashlib.sha256(b'').hexdigest()
  probe='index_probe_test.go.txt' if kind=='index' else 'workspace_probe_test.go.txt';assert inputs['probe_sha256']==hashlib.sha256((root/probe).read_bytes()).hexdigest()
  for p in d.glob('*.log'):
   for line in p.read_text().splitlines():
    if 'followup_measurement=' in line:
     r=json.loads(line.split('followup_measurement=',1)[1]);rows.setdefault((r['modules'],r['mode'],r['iteration']),{})[side]=r
    if 'lexical_payload=' in line:
     r=json.loads(line.split('lexical_payload=',1)[1]);payloads.setdefault(p.name.split('-payload-',1)[0],[]).append(r)
    if 'lexical_cold=' in line:std.add(json.loads(line.split('lexical_cold=',1)[1])['std_source_sha256'])
    if 'lexical_tokens=' in line:tokens.add(json.loads(line.split('lexical_tokens=',1)[1])['token_payload_sha256'])
assert len(rows)==12
for pair in rows.values():
 b,c=pair['baseline'],pair['candidate'];assert b['payload_sha256']==c['payload_sha256']
 if b['mode']=='counts':assert b['counts']['strict_calls']==c['counts']['strict_calls'] and c['counts']['standard_lex_calls']==0
for case,values in payloads.items():
 expected=next(x for x in s['payload_checks'] if x['case']==case);assert len(values)==4;assert all(x['payload_sha256']==expected['sha256'] and x['payload_bytes']==expected['bytes'] and x['occurrences']==expected['occurrences'] for x in values)
assert std=={s['std_source_sha256']} and tokens=={s['token_payload_sha256']}
assert s['metadata']['baseline-index']['source_sha256']['pkg/lexer/lexer.go']==s['metadata']['candidate-index']['source_sha256']['pkg/lexer/lexer.go']
print('Verified exact clean heads/probe/lexer hashes, two recorded fullInfo payload pairs,12recorded symbols pairs, strict counts and standard digests. Omitted full payload bytes were not regenerated.')
