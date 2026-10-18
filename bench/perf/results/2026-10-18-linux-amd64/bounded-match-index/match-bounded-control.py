from pathlib import Path
import os,subprocess,json,hashlib
root=Path('/workspace/manuscript');manifest=json.loads(Path('/tmp/manuscript-builder-range-matched-manifest.json').read_text());app=Path(manifest['program']['app']).resolve();original=(app/'main.go').read_text()
a=original.index('func area(');b=original.index('\nfunc ',a+1);area=original[a:b]
clone=area.replace('func area(','func area_bounded(').replace('rt.IntMultiply(r, int(3))','r * int(3)').replace('rt.IntMultiply(side, side)','side * side')
s=original[:b]+'\n'+clone+original[b:]
a=s.index('func bench_match(');b=s.index('\nfunc ',a+1);part=s[a:b].replace('area(ctx,','area_bounded(ctx,');s=s[:a]+part+s[b:]
s=s.replace('rt.RegisterSource(area, "area")','rt.RegisterSource(area, "area")\n rt.RegisterSource(area_bounded,"area")')
versions={'before':original,'clone':s}
a=s.index('func bench_match(');b=s.index('\nfunc ',a+1);part=s[a:b].replace('rt.IntAdd(ma, area_bounded(ctx, rt.List_Get[Shape](ctx, shapes, i%int(3), rt.Option[Shape]{})))','ma + area_bounded(ctx, rt.List_Get[Shape](ctx, shapes, i%int(3), rt.Option[Shape]{}))');assert part!=s[a:b];versions['clone-carry']=s[:a]+part+s[b:]
record={}
for label,source in versions.items():
 p=Path('/tmp/manuscript-match-bounded-'+label+'.go');p.write_text(source);overlay=p.with_suffix('.json');overlay.write_text(json.dumps({'Replace':{str(app/'main.go'):str(p)}}));binary='/tmp/manuscript-match-bounded-'+label
 subprocess.run([str(root/'toolchain/go/bin/go'),'build','-buildvcs=false','-trimpath','-ldflags=-s -w -buildid=','-overlay='+str(overlay),'-o',binary,'.'],cwd=app,env={**os.environ,'CGO_ENABLED':'0'},check=True)
 record[label]={'source_sha256':hashlib.sha256(source.encode()).hexdigest(),'binary_sha256':hashlib.sha256(Path(binary).read_bytes()).hexdigest()}
assert len({r['binary_sha256'] for r in record.values()})==3
Path('/tmp/manuscript-match-bounded-manifest.json').write_text(json.dumps(record,indent=2)+'\n')
