from pathlib import Path
import re,subprocess,os,json,hashlib
root=Path('/workspace/manuscript');binary='/tmp/manuscript-parity2-record-chunk-program';go=str(root/'toolchain/go/bin/go')
meta=subprocess.check_output([go,'version','-m',binary],text=True);key=re.search(r'/apps/([a-f0-9]+)',meta).group(1)
want=hashlib.sha256((root/'pkg/runtime/io.go').read_bytes()).hexdigest()
app=next(p for p in Path('/tmp/manuscript-cache/manuscript/workspaces').glob('*/apps/'+key) if hashlib.sha256((p.parents[1]/'pkg/runtime/io.go').read_bytes()).hexdigest()==want)
original=(app/'main.go').read_text();start=original.index('func got_line(');end=original.index('//line generated.go:1\nfunc say(',start)
replacement='func got_line(ctx *rt.Execution,input rt.ReadStream)bool{\n/*line src/main.ms:23*/return rt.Io_HasLine(ctx,input,rt.Option[int]{})\n}\n'
for version,s in [('before',original),('after',original[:start]+replacement+original[end:])]:
 source=Path('/tmp/manuscript-line-control-'+version+'.go');source.write_text(s)
 overlay=Path('/tmp/manuscript-line-control-'+version+'.json');overlay.write_text(json.dumps({'Replace':{str(app/'main.go'):str(source)}}))
 subprocess.run([go,'build','-buildvcs=false','-trimpath','-ldflags=-s -w -buildid=','-overlay='+str(overlay),'-o','/tmp/manuscript-line-control-'+version,'.'],cwd=app,env={**os.environ,'CGO_ENABLED':'0'},check=True)
Path('/tmp/manuscript-record-chunk-app').write_text(str(app))
