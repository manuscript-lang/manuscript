"""Losslessly retain generated payloads without committing repeated megabyte strings."""
import argparse
import gzip
import hashlib
import json
import pathlib
import re
import shutil

p=argparse.ArgumentParser()
p.add_argument('--source',type=pathlib.Path,required=True)
p.add_argument('--output',type=pathlib.Path,required=True)
a=p.parse_args()
a.output.mkdir(parents=True,exist_ok=False)
payload={}
for path in sorted(a.source.iterdir()):
    if path.suffix in ['.input','.out']:
        raw=path.read_bytes()
        payload[path.name]={'utf8':raw.decode(),'sha256':hashlib.sha256(raw).hexdigest(),'bytes':len(raw)}
    elif path.suffix in ['.json','.jsonl'] and not re.fullmatch(r'.+-(before|after|rust)-[0-5]\.json',path.name):
        shutil.copy2(path,a.output/path.name)
if payload:
    raw=json.dumps(payload,ensure_ascii=False,separators=(',',':')).encode()
    packed=gzip.compress(raw,mtime=0)
    (a.output/'payloads.json.gz').write_bytes(packed)
    restored=json.loads(gzip.decompress(packed))
    for name,item in restored.items():
        data=item['utf8'].encode()
        if data!=(a.source/name).read_bytes() or len(data)!=item['bytes'] or hashlib.sha256(data).hexdigest()!=item['sha256']:
            raise ValueError('payload round trip changed bytes')
    manifest={'encoding':'gzip-compressed JSON; utf8 fields encode exact original bytes',
              'compressed_sha256':hashlib.sha256(packed).hexdigest(),'uncompressed_sha256':hashlib.sha256(raw).hexdigest(),
              'files':{name:{'sha256':item['sha256'],'bytes':item['bytes']} for name,item in payload.items()}}
    (a.output/'payloads-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('Retained complete records and',len(payload),'byte-verified payloads')
