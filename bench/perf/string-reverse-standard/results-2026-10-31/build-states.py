import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

tree=Path('/workspace/reverse-std-perf')
root=Path('/workspace/manuscript')
out=Path(__file__).resolve().parent
compiler=Path('/workspace/byte-search-evidence/fresh-main-988/ms-compiler')
names=['crates/ms-rt/src/string.rs','crates/ms-rt/src/vec.rs']
digest=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
baseline={n:subprocess.check_output(['git','show','HEAD:'+n],cwd=tree) for n in names}
reverse={n:(tree/n).read_bytes() for n in names}
record={'complete':False,'base':'98854115f95bfeddbaa362382bfcff85c0499752',
        'compiler':{'path':str(compiler),'sha256':digest(compiler)},'commands':[],'states':{}}
def save():
    (out/'states.json').write_text(json.dumps(record,indent=2)+'\n')
def run(args,label,extra=None):
    env=os.environ.copy();env.update(extra or {})
    with (out/(label+'.log')).open('wb') as log:
        p=subprocess.run(args,cwd=tree,env=env,stdout=log,stderr=subprocess.STDOUT)
    record['commands'].append({'argv':args,'extra_env':extra or {},'exit':p.returncode,'log':label+'.log'})
    save();p.check_returncode()
subprocess.run(['git','apply','/workspace/byte-search-evidence/fresh-main-988/production.patch'],cwd=tree,check=True)
both={n:(tree/n).read_bytes() for n in names}
for n in names:(tree/n).write_bytes(baseline[n])
subprocess.run(['git','apply','/workspace/byte-search-evidence/fresh-main-988/production.patch'],cwd=tree,check=True)
word={n:(tree/n).read_bytes() for n in names}
sources={'reverse':root/'bench/perf/string-normalization-rollback/inputs/reverse-full.ms',
         'normalize':root/'bench/perf/string-normalize-ascii/main.ms',
         'byte':root/'bench/perf/bytes-index/main.ms',
         'lines':root/'bench/perf/string-lines/main.ms',
         'text':Path('/workspace/text-discovery/text-discovery.ms')}
record['inputs']={s:{'path':str(p),'sha256':digest(p)} for s,p in sources.items()}
try:
    for label,state in [('reverse',reverse),('both',both),('word',word),('baseline',baseline)]:
        for n in names:(tree/n).write_bytes(state[n])
        folder=out/'states'/label;folder.mkdir(parents=True)
        for n in names:shutil.copyfile(tree/n,folder/(Path(n).name+'.txt'))
        (folder/'production.patch').write_bytes(subprocess.check_output(['git','diff','--',*names],cwd=tree))
        run(['cargo','xtask','runtime'],label+'-runtime-build')
        archive=out/(label+'.a');shutil.copyfile(tree/'target/ms-native/libms_native.a',archive)
        entry={'sources':{n:digest(tree/n) for n in names},'archive_sha256':digest(archive),'programs':{}}
        record['states'][label]=entry;save()
        for suite,source in sources.items():
            program=out/(label+'-'+suite)
            run([str(compiler),'build',str(source),'--build-type','Release','-o',str(program)],label+'-'+suite+'-build',{'MS_RT_LIB':str(archive)})
            entry['programs'][suite]={'path':str(program),'sha256':digest(program)};save()
    for label in ['baseline','reverse','both']:
        for profile in ['Debug','Release']:
            run([str(compiler),'test','tests/e2e/testdata/stdlib/string-reverse-standard.ms','--build-type',profile],
                label+'-source-'+profile.lower(),{'MS_RT_LIB':str(out/(label+'.a'))})
    for profile in ['Debug','Release']:
        run([str(compiler),'test',str(root/'tests/e2e/testdata/stdlib/bytes-index-search.ms'),'--build-type',profile],
            'both-byte-source-'+profile.lower(),{'MS_RT_LIB':str(out/'both.a')})
finally:
    for n in names:(tree/n).write_bytes(reverse[n])
    run(['cargo','xtask','runtime'],'restored-reverse-runtime-build')
record['restored_sources']={n:digest(tree/n) for n in names}
assert record['restored_sources']==record['states']['reverse']['sources']
assert digest(tree/'target/ms-native/libms_native.a')==record['states']['reverse']['archive_sha256']
record['complete']=True;save()
