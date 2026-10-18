from pathlib import Path
import json,os,subprocess
root=Path('/workspace/manuscript');app=Path(json.loads(Path('/tmp/manuscript-mul-apps.json').read_text())['after'])
source=(app/'main.go').read_text();assert source.count('Acc_bump(ctx, acc, int(1))')==1
for name,s in [('before',source),('after',source.replace('Acc_bump(ctx, acc, int(1))','acc.Total += int(1)'))]:
 path=Path('/tmp/manuscript-record-control-'+name+'.go');path.write_text(s)
 overlay=Path('/tmp/manuscript-record-control-'+name+'.json');overlay.write_text(json.dumps({'Replace':{str(app/'main.go'):str(path)}}))
 subprocess.run([str(root/'toolchain/go/bin/go'),'build','-buildvcs=false','-trimpath','-ldflags=-s -w -buildid=','-overlay='+str(overlay),'-o','/tmp/manuscript-record-control-'+name,'.'],cwd=app,env={**os.environ,'CGO_ENABLED':'0'},check=True)
