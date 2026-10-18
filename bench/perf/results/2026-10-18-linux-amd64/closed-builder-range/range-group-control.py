from pathlib import Path
import os,json,subprocess,hashlib
root=Path('/workspace/manuscript');app=Path(json.loads(Path('/tmp/manuscript-aggregate-matched-manifest.json').read_text())['program']['app']).resolve();base=(app/'main.go').read_text();versions={'range':base,'builder-range':Path('/tmp/manuscript-builder-group.go').read_text(),'clone-range':Path('/tmp/manuscript-match-clone-clone-carry.go').read_text()};record={}
for label,s in versions.items():
 a=s.index('func bench_for_list');b=s.index('\nfunc ',a+1);part=s[a:b];start=part.index('\tvar t6 uint32');end=part.index('\n//line src/main.ms:206',start)
 part=part[:start]+'''items:=big.Items
 for index:=0;index<len(items); {
  end:=len(items)
  if len(items)-index>63 {end=index+63}
  for ;index<end;index++ {x:=items[index];fs+=x}
  if index<len(items) {x:=items[index];rt.CheckCancelled(ctx);fs+=x;index++}
 }
'''+part[end:];s=s[:a]+part+s[b:];p=Path('/tmp/manuscript-range-group-'+label+'.go');p.write_text(s);ov=p.with_suffix('.json');ov.write_text(json.dumps({'Replace':{str(app/'main.go'):str(p)}}));binary='/tmp/manuscript-range-group-'+label
 subprocess.run([str(root/'toolchain/go/bin/go'),'build','-buildvcs=false','-trimpath','-ldflags=-s -w -buildid=','-overlay='+str(ov),'-o',binary,'.'],cwd=app,env={**os.environ,'CGO_ENABLED':'0'},check=True)
 record[label]={'source_sha256':hashlib.sha256(s.encode()).hexdigest(),'binary_sha256':hashlib.sha256(Path(binary).read_bytes()).hexdigest()}
Path('/tmp/manuscript-range-group-manifest.json').write_text(json.dumps(record,indent=2)+'\n')
