from pathlib import Path
import subprocess,re,os,hashlib,json
root=Path('/workspace/manuscript');go=str(root/'toolchain/go/bin/go');apps={}
for name,binary,numeric in [('before','/tmp/manuscript-parity2-mul-range-program','/tmp/manuscript-before-mul-callback.go'),('after','/tmp/manuscript-parity2-mul-callback-program',str(root/'pkg/runtime/numeric.go'))]:
 metadata=subprocess.check_output([go,'version','-m',binary],text=True);key=re.search(r'/apps/([a-f0-9]+)',metadata).group(1)
 want=hashlib.sha256(Path(numeric).read_bytes()).hexdigest()
 choices=list(Path('/tmp/manuscript-cache/manuscript/workspaces').glob('*/apps/'+key))
 app=next(p for p in choices if hashlib.sha256((p.parents[1]/'pkg/runtime/numeric.go').read_bytes()).hexdigest()==want)
 apps[name]=str(app)
 subprocess.run([go,'build','-buildvcs=false','-trimpath','-ldflags=-buildid=','-o','/tmp/manuscript-mul-'+name+'-symbols','.'],cwd=app,env={**os.environ,'CGO_ENABLED':'0'},check=True)
 for fn in ['bench_generic','bench_length','bench_method','bench_try','area']:
  result=subprocess.check_output([go,'tool','objdump','-s','^main.'+fn+'$','/tmp/manuscript-mul-'+name+'-symbols'],text=True)
  Path('/tmp/manuscript-mul-'+name+'-'+fn+'.asm').write_text(result)
Path('/tmp/manuscript-mul-apps.json').write_text(json.dumps(apps))
