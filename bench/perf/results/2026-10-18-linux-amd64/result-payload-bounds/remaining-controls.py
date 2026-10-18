from pathlib import Path
import subprocess,os,json,re,hashlib
root=Path('/workspace/manuscript');app=Path(Path('/tmp/manuscript-presence-app').read_text()).resolve();original=(app/'main.go').read_text()
def edit_function(s,name,edit):
 a=s.index('func '+name+'('); b=s.find('\nfunc ',a+1)
 if b<0:b=len(s)
 return s[:a]+edit(s[a:b])+s[b:]
match=edit_function(original,'area',lambda s:s.replace('rt.IntMultiply(r, int(3))','r * int(3)').replace('rt.IntMultiply(side, side)','side * side'))
try_carry=edit_function(original,'bench_try',lambda s:s.replace('rt.IntAdd(tr, v)','tr + v'))
try_all=try_carry.replace('rt.IntAdd(n, int(1))','n + int(1)')
combined=edit_function(try_all,'area',lambda s:s.replace('rt.IntMultiply(r, int(3))','r * int(3)').replace('rt.IntMultiply(side, side)','side * side'))
combined=edit_function(combined,'bench_match',lambda s:s.replace('rt.IntAdd(ma, area(ctx, rt.List_Get[Shape](ctx, shapes, i%int(3), rt.Option[Shape]{})))','ma + area(ctx, rt.List_Get[Shape](ctx, shapes, i%int(3), rt.Option[Shape]{}))'))
def chunk(s):
 m=re.search(r'for (\w+) < int\((\d+)\) \{',s);assert m
 start=m.end();depth=1;end=start
 while depth:depth+=(s[end]=='{')-(s[end]=='}');end+=1
 body=s[start:end-1];poll=body.index('rt.CheckCancelled(ctx)');close=body.index('}',poll);phase=body[:close+1];body=body[close+1:]
 counter,limit=m.group(1),int(m.group(2));initial=re.search(r'\('+counter+r'-(\w+)\+1\)',phase);assert initial
 replacement=f'_ = {initial.group(1)}\nfor {counter}<int({limit}){{\nchunkEnd:=int({limit})\nif int({limit})-{counter}>63 {{chunkEnd={counter}+63}}\nfor {counter}<chunkEnd{{{body}}}\nif {counter}<int({limit}){{rt.CheckCancelled(ctx)\n{body}}}\n}}'
 return s[:m.start()]+replacement+s[end:]
combined=edit_function(combined,'bench_generic',chunk)
versions={'before':original,'match':match,'try-carry':try_carry,'try-all':try_all,'combined':combined}
manifest={}
for label,s in versions.items():
 p=Path('/tmp/manuscript-remaining-'+label+'.go');p.write_text(s)
 overlay=p.with_suffix('.json');overlay.write_text(json.dumps({'Replace':{str(app/'main.go'):str(p)}}))
 binary='/tmp/manuscript-remaining-'+label
 subprocess.run([str(root/'toolchain/go/bin/go'),'build','-buildvcs=false','-trimpath','-ldflags=-s -w -buildid=','-overlay='+str(overlay),'-o',binary,'.'],cwd=app,env={**os.environ,'CGO_ENABLED':'0'},check=True)
 manifest[label]={'source_sha256':hashlib.sha256(s.encode()).hexdigest(),'binary_sha256':hashlib.sha256(Path(binary).read_bytes()).hexdigest()}
assert len({m['binary_sha256'] for m in manifest.values()})==len(versions)
Path('/tmp/manuscript-remaining-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
