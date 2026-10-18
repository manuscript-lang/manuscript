from pathlib import Path
import os,json,subprocess,hashlib
root=Path('/workspace/manuscript');app=Path(json.loads(Path('/tmp/manuscript-aggregate-matched-manifest.json').read_text())['program']['app']).resolve();s=(app/'main.go').read_text();a=s.index('func bench_string(');b=s.index('\nfunc ',a+1);part=s[a:b];print(part)
start=part.index('\tt4 := i');end=part.index('\n//line src/main.ms:72',start)
part=part[:start]+'''for i<50000 {
 n:=50000-i
 if n>63 {n=63}
 rt.StringBuilder_Append(ctx,sb,"'''+('x'*63)+'''"[:n])
 i+=n
 if i<50000 {
 rt.CheckCancelled(ctx)
 rt.StringBuilder_Append(ctx,sb,"x")
 i++
 }
}
'''+part[end:];s=s[:a]+part+s[b:];p=Path('/tmp/manuscript-builder-group.go');p.write_text(s);ov=p.with_suffix('.json');ov.write_text(json.dumps({'Replace':{str(app/'main.go'):str(p)}}));subprocess.run([str(root/'toolchain/go/bin/go'),'build','-buildvcs=false','-trimpath','-ldflags=-s -w -buildid=','-overlay='+str(ov),'-o','/tmp/manuscript-builder-group','.'],cwd=app,env={**os.environ,'CGO_ENABLED':'0'},check=True)
Path('/tmp/manuscript-builder-group-manifest.json').write_text(json.dumps({'source_sha256':hashlib.sha256(s.encode()).hexdigest(),'binary_sha256':hashlib.sha256(Path('/tmp/manuscript-builder-group').read_bytes()).hexdigest()},indent=2)+'\n')
