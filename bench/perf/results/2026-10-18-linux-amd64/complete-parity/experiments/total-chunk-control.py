from pathlib import Path
import os,subprocess,re,json
root=Path('/workspace/manuscript');app=Path(Path('/tmp/manuscript-presence-app').read_text());original=(app/'main.go').read_text();changes=[]
for m in re.finditer(r'for (\w+) < int\((\d+)\) \{',original):
 owner=re.findall(r'\nfunc (\w+)\(',original[:m.start()])[-1]
 if owner not in {'bench_generic','bench_method'}:continue
 start=m.end();depth=1;end=start
 while depth:
  depth+=(original[end]=='{')-(original[end]=='}');end+=1
 body=original[start:end-1];poll=body.index('rt.CheckCancelled(ctx)');close=body.index('}',poll);phase=body[:close+1];body=body[close+1:]
 counter,limit=m.group(1),int(m.group(2));initial=re.search(r'\('+counter+r'-(\w+)\+1\)',phase);assert initial
 name='chunkEnd'+str(len(changes));replacement=f'_ = {initial.group(1)}\nfor {counter}<int({limit}){{\n{name}:=int({limit})\nif int({limit})-{counter}>63 {{{name}={counter}+63}}\nfor {counter}<{name}{{{body}}}\nif {counter}<int({limit}){{rt.CheckCancelled(ctx)\n{body}}}\n}}'
 changes.append((m.start(),end,replacement))
s=original
for start,end,replacement in reversed(changes):s=s[:start]+replacement+s[end:]
for version,text in [('before',original),('after',s)]:
 path=Path('/tmp/manuscript-total-chunk-'+version+'.go');path.write_text(text)
 overlay=Path('/tmp/manuscript-total-chunk-'+version+'.json');overlay.write_text(json.dumps({'Replace':{str(app/'main.go'):str(path)}}))
 subprocess.run([str(root/'toolchain/go/bin/go'),'build','-buildvcs=false','-trimpath','-ldflags=-s -w -buildid=','-overlay='+str(overlay),'-o','/tmp/manuscript-total-chunk-'+version,'.'],cwd=app,env={**os.environ,'CGO_ENABLED':'0'},check=True)
print('loops',len(changes))
