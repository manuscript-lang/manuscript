from pathlib import Path
import subprocess,os,re,json,hashlib
root=Path('/workspace/manuscript');go=root/'toolchain/go/bin/go'
binary=root/'.artifacts/perf-binaries/result-bounds-program'
key=re.search('/apps/([a-f0-9]+)',subprocess.check_output([str(go),'version','-m',str(binary)],text=True)).group(1)
apps=list(Path('/tmp/manuscript-cache/manuscript/workspaces').glob('*/apps/'+key))
app=next(p.resolve() for p in apps if all((p.parents[1]/'pkg/runtime'/name).read_bytes()==(root/'pkg/runtime'/name).read_bytes() for name in ['numeric.go','io.go','fs.go','time.go','encoding.go']))
original=(app/'main.go').read_text()
def aggregate(s,name,carry,delta,affine=False):
 a=s.index('func '+name+'(');b=s.find('\nfunc ',a+1)
 part=s[a:b]
 m=list(re.finditer(r'for (\w+) < int\(1000000\) \{',part))[-1]
 start=m.end();end=start;depth=1
 while depth:depth+=(part[end]=='{')-(part[end]=='}');end+=1
 i=m.group(1)
 # Preserve compiler-created starting-counter local when replacing its uses.
 start_local=re.search(r'(\w+) := '+i+r'\s*\n\s*/\*line[^*]*\*/for',part[:start])
 unused='_ = '+start_local.group(1)+'\n' if start_local else ''
 addition=f'n*{i}+n*(n-1)/2' if affine else f'n*({delta})'
 replacement=unused+f'''for {i}<int(1000000){{
n:=int(1000000)-{i}
if n>63 {{n=63}}
{carry} += {addition}
{i}+=n
if {i}<int(1000000){{rt.CheckCancelled(ctx)
{carry} += {delta}
{i}++
}}
}}'''
 part=part[:m.start()]+replacement+part[end:]
 return s[:a]+part+s[b:]
versions={'before':original}
for label,functions in [('scalars',['bench_generic','bench_length']),('all',['bench_generic','bench_method','bench_length'])]:
 s=original
 for name in functions:
  if name=='bench_generic':s=aggregate(s,name,'g','i',True)
  elif name=='bench_method':s=aggregate(s,name,'acc.Total','int(1)')
  else:s=aggregate(s,name,'ln','int(100)')
 versions[label]=s
manifest={}
for label,s in versions.items():
 source=Path('/tmp/manuscript-aggregate-'+label+'.go');source.write_text(s)
 overlay=source.with_suffix('.json');overlay.write_text(json.dumps({'Replace':{str(app/'main.go'):str(source)}}))
 target='/tmp/manuscript-aggregate-'+label
 subprocess.run([str(go),'build','-buildvcs=false','-trimpath','-ldflags=-s -w -buildid=','-overlay='+str(overlay),'-o',target,'.'],cwd=app,env={**os.environ,'CGO_ENABLED':'0'},check=True)
 manifest[label]={'source_sha256':hashlib.sha256(s.encode()).hexdigest(),'binary_sha256':hashlib.sha256(Path(target).read_bytes()).hexdigest()}
assert len({x['binary_sha256'] for x in manifest.values()})==len(versions)
Path('/tmp/manuscript-aggregate-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
