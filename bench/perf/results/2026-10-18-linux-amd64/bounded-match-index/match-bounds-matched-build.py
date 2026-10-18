from pathlib import Path
import subprocess,re,os,json,hashlib
root=Path('/workspace/manuscript');go=root/'toolchain/go/bin/go';manifest={}
for kind in ['program','stdlib']:
 binary=root/'.artifacts/perf-binaries'/('match-bounds-'+kind);key=re.search('/apps/([a-f0-9]+)',subprocess.check_output([str(go),'version','-m',str(binary)],text=True)).group(1)
 app=next(p.resolve() for p in Path('/tmp/manuscript-cache/manuscript/workspaces').glob('*/apps/'+key) if all((p.parents[1]/'pkg/runtime'/name).read_bytes()==(root/'pkg/runtime'/name).read_bytes() for name in ['numeric.go','io.go','fs.go','time.go','encoding.go']))
 output=root/'.artifacts/perf-binaries'/('match-bounds-matched-'+kind)
 subprocess.run([str(go),'build','-buildvcs=false','-trimpath','-ldflags=-s -w -buildid=','-o',str(output),'.'],cwd=app,env={**os.environ,'CGO_ENABLED':'0'},check=True)
 manifest[kind]={'app':str(app),'binary':str(output),'source_sha256':hashlib.sha256((app/'main.go').read_bytes()).hexdigest(),'binary_sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'metadata':subprocess.check_output([str(go),'version','-m',str(output)],text=True)}
Path('/tmp/manuscript-match-bounds-matched-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
