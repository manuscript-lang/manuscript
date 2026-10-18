from pathlib import Path
import json,os,subprocess
root=Path('/workspace/manuscript');app=Path(json.loads(Path('/tmp/manuscript-mul-apps.json').read_text())['after'])
main=(app/'main.go').read_text();assert main.count('rt.LocalIntMap_Get(ctx, m, i)')==1
runtime=app.parents[1]/'pkg/runtime/local_int_map.go'
helper=Path('/tmp/manuscript-map-presence-helper.go');helper.write_text(runtime.read_text()+'\nfunc LocalIntMap_GetPresent(_ *Execution,m *Map[int,int],key int)int{return m.index[key]}\n')
for name,s in [('before',main),('after',main.replace('rt.LocalIntMap_Get(ctx, m, i)','rt.Option[int]{Some:true,Val:rt.LocalIntMap_GetPresent(ctx,m,i)}'))]:
 path=Path('/tmp/manuscript-map-presence-'+name+'.go');path.write_text(s)
 overlay=Path('/tmp/manuscript-map-presence-'+name+'.json');overlay.write_text(json.dumps({'Replace':{str(app/'main.go'):str(path),str(runtime):str(helper)}}))
 subprocess.run([str(root/'toolchain/go/bin/go'),'build','-buildvcs=false','-trimpath','-ldflags=-s -w -buildid=','-overlay='+str(overlay),'-o','/tmp/manuscript-map-presence-'+name,'.'],cwd=app,env={**os.environ,'CGO_ENABLED':'0'},check=True)
