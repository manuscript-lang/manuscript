from pathlib import Path
import os,json,subprocess,hashlib
root=Path('/workspace/manuscript');m=json.loads(Path('/tmp/manuscript-aggregate-matched-manifest.json').read_text());app=Path(m['program']['app']).resolve();runtime=app.parents[1]/'pkg/runtime/numeric.go';a=(app/'main.go').read_text();s=runtime.read_text()
s+='''
func IntMultiplyLiteral(a,b,lo,hi int) int {return intMultiplyLiteral(a,b,lo,hi,intOverflow)}
func intMultiplyLiteral(a,b,lo,hi int,overflow func()) int {
 if uint(a)-uint(lo)>uint(hi)-uint(lo) {overflow()}
 return a*b
}
func IntSquare(a int) int {return intSquare(a,intOverflow)}
func intSquare(a int,overflow func()) int {
 limit:=int64(3037000499)
 if bits.UintSize==32 {limit=46340}
 if uint64(int64(a))+uint64(limit)>2*uint64(limit) {overflow()}
 return a*a
}
'''
a=a.replace('rt.IntMultiply(r, int(3))','rt.IntMultiplyLiteral(r, int(3), -3074457345618258602, 3074457345618258602)').replace('rt.IntMultiply(side, side)','rt.IntSquare(side)')
p=Path('/tmp/manuscript-multiply-shape-runtime.go');p.write_text(s);q=Path('/tmp/manuscript-multiply-shape-main.go');q.write_text(a);ov=Path('/tmp/manuscript-multiply-shape-overlay.json');ov.write_text(json.dumps({'Replace':{str(runtime):str(p),str(app/'main.go'):str(q)}}))
subprocess.run([str(root/'toolchain/go/bin/go'),'build','-buildvcs=false','-trimpath','-ldflags=-s -w -buildid=','-overlay='+str(ov),'-o','/tmp/manuscript-multiply-shape','.'],cwd=app,env={**os.environ,'CGO_ENABLED':'0'},check=True)
Path('/tmp/manuscript-multiply-shape-manifest.json').write_text(json.dumps({'app_source_sha256':hashlib.sha256(a.encode()).hexdigest(),'runtime_source_sha256':hashlib.sha256(s.encode()).hexdigest(),'binary_sha256':hashlib.sha256(Path('/tmp/manuscript-multiply-shape').read_bytes()).hexdigest()},indent=2)+'\n')
