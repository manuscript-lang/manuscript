from pathlib import Path
import os,subprocess,re,json
root=Path('/workspace/manuscript');app=Path(Path('/tmp/manuscript-presence-app').read_text());original=(app/'main.go').read_text()
for variant,functions in [('before',set()),('generic',{'bench_generic'}),('all',{'bench_generic','bench_try','bench_method','bench_length','bench_for_list','bench_int_eq','bench_map','bench_match','bench_string'})]:
 s=original;changes=[]
 for m in re.finditer(r'rt.CheckCancelled\(ctx\)',s):
  owner=re.findall(r'\nfunc (\w+)\(',s[:m.start()])[-1]
  if owner in functions:changes.append((m.start(),m.end(),'rt.PollIndex(ctx,63)'))
 for start,end,replacement in reversed(changes):s=s[:start]+replacement+s[end:]
 path=Path('/tmp/manuscript-loop-poll-'+variant+'.go');path.write_text(s)
 overlay=Path('/tmp/manuscript-loop-poll-'+variant+'.json');overlay.write_text(json.dumps({'Replace':{str(app/'main.go'):str(path)}}))
 subprocess.run([str(root/'toolchain/go/bin/go'),'build','-buildvcs=false','-trimpath','-ldflags=-s -w -buildid=','-overlay='+str(overlay),'-o','/tmp/manuscript-loop-poll-'+variant,'.'],cwd=app,env={**os.environ,'CGO_ENABLED':'0'},check=True)
 print(variant,len(changes))
