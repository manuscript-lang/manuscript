from pathlib import Path
import subprocess,os,re,json,hashlib,struct
root=Path('/workspace/manuscript');go=root/'toolchain/go/bin/go';manifest={}
for label,source in [('before-program','result-before-program'),('after-program','result-bounds-program'),('before-stdlib','result-before-stdlib'),('after-stdlib','result-bounds-stdlib')]:
 binary=root/'.artifacts/perf-binaries'/source;key=re.search('/apps/([a-f0-9]+)',subprocess.check_output([str(go),'version','-m',str(binary)],text=True)).group(1)
 app=next(p.resolve() for p in Path('/tmp/manuscript-cache/manuscript/workspaces').glob('*/apps/'+key) if all((p.parents[1]/'pkg/runtime'/name).read_bytes()==(root/'pkg/runtime'/name).read_bytes() for name in ['numeric.go','io.go','fs.go','time.go','encoding.go']))
 output=root/'.artifacts/perf-binaries'/('result-matched-'+label)
 subprocess.run([str(go),'build','-buildvcs=false','-trimpath','-ldflags=-s -w -buildid=','-o',str(output),'.'],cwd=app,env={**os.environ,'CGO_ENABLED':'0'},check=True)
 manifest[label]={'source_sha256':hashlib.sha256((app/'main.go').read_bytes()).hexdigest(),'binary_sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'app_path':str(app),'binary':str(output),'metadata':subprocess.check_output([str(go),'version','-m',str(output)],text=True)}
assert manifest['before-stdlib']['source_sha256']==manifest['after-stdlib']['source_sha256']
assert manifest['before-stdlib']['binary_sha256']==manifest['after-stdlib']['binary_sha256']
Path('/tmp/manuscript-result-matched-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('Library Go source and normalized executables are byte-identical.')
