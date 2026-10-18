from pathlib import Path
import os,subprocess,re,json,hashlib
root=Path('/workspace/manuscript');go=str(root/'toolchain/go/bin/go')
meta=subprocess.check_output([go,'version','-m','/tmp/manuscript-parity2-presence-program'],text=True);key=re.search(r'/apps/([a-f0-9]+)',meta).group(1)
want=hashlib.sha256((root/'pkg/runtime/io.go').read_bytes()).hexdigest()
app=next(p for p in Path('/tmp/manuscript-cache/manuscript/workspaces').glob('*/apps/'+key) if hashlib.sha256((p.parents[1]/'pkg/runtime/io.go').read_bytes()).hexdigest()==want)
original=(app/'main.go').read_text();changes=[]
for m in re.finditer(r'for (\w+) < int\((\d+)\) \{',original):
 start=m.end();depth=1;end=start
 while depth:
  depth+=(original[end]=='{')-(original[end]=='}');end+=1
 body=original[start:end-1];counter=m.group(1)
 step=re.search(r'(?m)^\t*'+counter+r' = '+counter+r' \+ int\(1\)\n\s*$',body)
 if step:
  body=body[:step.start()]+body[step.end():]
  changes.append((m.start(),end,f'for ; {counter} < int({m.group(2)}); {counter} = {counter} + int(1) {{'+body+'}'))
s=original
for start,end,replacement in reversed(changes):s=s[:start]+replacement+s[end:]
for version,text in [('before',original),('after',s)]:
 path=Path('/tmp/manuscript-post-control-'+version+'.go');path.write_text(text)
 overlay=Path('/tmp/manuscript-post-control-'+version+'.json');overlay.write_text(json.dumps({'Replace':{str(app/'main.go'):str(path)}}))
 subprocess.run([go,'build','-buildvcs=false','-trimpath','-ldflags=-s -w -buildid=','-overlay='+str(overlay),'-o','/tmp/manuscript-post-control-'+version,'.'],cwd=app,env={**os.environ,'CGO_ENABLED':'0'},check=True)
print('loops',len(changes))
Path('/tmp/manuscript-presence-app').write_text(str(app))
# A separate runtime-only comparison isolates multiplication outlining without
# changing checked Go or adding padding.
overlay=Path('/tmp/manuscript-presence-no-mul.json');overlay.write_text(json.dumps({'Replace':{str(app.parents[1]/'pkg/runtime/numeric.go'):'/tmp/manuscript-before-mul-callback.go'}}))
subprocess.run([go,'build','-buildvcs=false','-trimpath','-ldflags=-s -w -buildid=','-overlay='+str(overlay),'-o','/tmp/manuscript-presence-no-mul','.'],cwd=app,env={**os.environ,'CGO_ENABLED':'0'},check=True)
