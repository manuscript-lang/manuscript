import hashlib
import json
import os
from pathlib import Path
import subprocess

out=Path(__file__).resolve().parent
root=Path('/workspace/manuscript')
compiler='/workspace/byte-search-evidence/fresh-main-988/ms-compiler'
digest=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
record={'complete':False,'commands':[],'programs':{},'sources':{}}
def save():(out/'rss-builds.json').write_text(json.dumps(record,indent=2)+'\n')
def run(args,label,extra=None):
    env=os.environ.copy();env.update(extra or {})
    with (out/(label+'.log')).open('wb') as log:
        r=subprocess.run(args,cwd=root,env=env,stdout=log,stderr=subprocess.STDOUT)
    record['commands'].append({'argv':args,'extra_env':extra or {},'exit':r.returncode,'log':label+'.log'})
    save();r.check_returncode()
for mode in ['ascii','mixed']:
    source=out/('rss-'+mode+'.ms');record['sources'][str(source)]=digest(source)
    for label in ['baseline','word','reverse','both']:
        program=out/(label+'-rss-'+mode)
        run([compiler,'build',str(source),'--build-type','Release','-o',str(program)],
            label+'-rss-'+mode+'-build',{'MS_RT_LIB':str(out/(label+'.a'))})
        record['programs'][label+'-'+mode]={'path':str(program),'sha256':digest(program)};save()
    program=out/('rust-rss-'+mode)
    args=['rustc','--edition=2024','-C','opt-level=3','-C','overflow-checks=yes','-C','force-frame-pointers=yes',str(out/'rss.rs'),'-o',str(program)]
    if mode=='mixed':args+=['--cfg','feature="mixed"']
    run(args,'rust-rss-'+mode+'-build')
    record['programs']['rust-'+mode]={'path':str(program),'sha256':digest(program)};save()
source=root/'bench/perf/representative/rss.c';record['sources'][str(source)]=digest(source)
record['sources'][str(out/'rss.rs')]=digest(out/'rss.rs')
run(['cc','-O2',str(source),'-o',str(out/'rss-launcher')],'rss-launcher-build')
run(['cc','--version'],'cc-version')
run(['rustc','-vV'],'rustc-version')
record['launcher_sha256']=digest(out/'rss-launcher')
record['complete']=True;save()
