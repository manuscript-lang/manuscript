from pathlib import Path
import subprocess,os,json,hashlib
root=Path('/workspace/manuscript');m=json.loads(Path('/tmp/manuscript-aggregate-matched-manifest.json').read_text()); app=Path(m['program']['app']).resolve();runtime=app.parents[1]/'pkg/runtime/string.go';s=runtime.read_text();a=s.index('func StringBuilder_Append(');b=s.index('\nfunc StringBuilder_Freeze',a)
new='''func StringBuilder_Append(_ *Execution, b *StringBuilder, value string) Unit {return stringBuilderAppend(b,value,stringBuilderSealed)}
func stringBuilderAppend(b *StringBuilder,value string,sealed func()) Unit {
 if b.sealed {sealed()}
 b.text=append(b.text,value...)
 return Unit{}
}
func stringBuilderSealed(){Raise("builder is sealed")}
'''
versions={'before':s,'after':s[:a]+new+s[b:]};record={}
for label,src in versions.items():
 p=Path('/tmp/manuscript-builder-callback-'+label+'.go');p.write_text(src);ov=p.with_suffix('.json');ov.write_text(json.dumps({'Replace':{str(runtime):str(p)}}));binary='/tmp/manuscript-builder-callback-'+label
 with open('/tmp/manuscript-builder-inline-'+label+'.log','w') as log:
  subprocess.run([str(root/'toolchain/go/bin/go'),'build','-buildvcs=false','-trimpath','-ldflags=-s -w -buildid=','-gcflags=github.com/manuscript-lang/manuscript/pkg/runtime=-m=2','-overlay='+str(ov),'-o',binary,'.'],cwd=app,env={**os.environ,'CGO_ENABLED':'0'},stderr=log,check=True)
 record[label]={'runtime_sha256':hashlib.sha256(src.encode()).hexdigest(),'binary_sha256':hashlib.sha256(Path(binary).read_bytes()).hexdigest()}
assert record['before']['binary_sha256']!=record['after']['binary_sha256']
Path('/tmp/manuscript-builder-callback-manifest.json').write_text(json.dumps(record,indent=2)+'\n')
