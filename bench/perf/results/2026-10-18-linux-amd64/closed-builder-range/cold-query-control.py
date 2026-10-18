from pathlib import Path
import json,subprocess,os,hashlib
root=Path('/workspace/manuscript');m=json.loads(Path('/tmp/manuscript-aggregate-matched-manifest.json').read_text());app=Path(m['program']['app']).resolve();s=(app/'main.go').read_text();clone=Path('/tmp/manuscript-match-clone-clone-carry.go').read_text();versions={'plain':s.replace('rt.CheckCancelled(ctx)','rt.PollIndex(ctx,63)'),'clone':clone.replace('rt.CheckCancelled(ctx)','rt.PollIndex(ctx,63)')};record={}
for label,s in versions.items():
 p=Path('/tmp/manuscript-cold-query-'+label+'.go');p.write_text(s);ov=p.with_suffix('.json');ov.write_text(json.dumps({'Replace':{str(app/'main.go'):str(p)}}));binary='/tmp/manuscript-cold-query-'+label
 subprocess.run([str(root/'toolchain/go/bin/go'),'build','-buildvcs=false','-trimpath','-ldflags=-s -w -buildid=','-overlay='+str(ov),'-o',binary,'.'],cwd=app,env={**os.environ,'CGO_ENABLED':'0'},check=True)
 record[label]={'source_sha256':hashlib.sha256(s.encode()).hexdigest(),'binary_sha256':hashlib.sha256(Path(binary).read_bytes()).hexdigest()}
Path('/tmp/manuscript-cold-query-manifest.json').write_text(json.dumps(record,indent=2)+'\n')
