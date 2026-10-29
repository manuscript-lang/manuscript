from pathlib import Path
import os,subprocess,json,hashlib,time
root=Path('/tmp/string-round2/integration-performance');root.mkdir()
compiler=Path('/tmp/string-round2/integrated-inputs/ms')
variants={'before':Path('/tmp/string-round2/integration-before-native'),'after':Path('/tmp/string-round2/integrated-inputs')}
suites=[('normalize-full','string-normalize-ascii','main.ms','identities.json',7),('normalize-focused','string-normalize-ascii','focused-controls.ms','focused-identities.json',9),('reverse-full','string-reverse-ascii','main.ms','identities.json',7),('reverse-focused','string-reverse-ascii','focused-controls.ms','focused-identities.json',9)]
record={'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'integration_commit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'before_main':'db975ce2f01ddf8da108ec9045ecaf66a63ab22c','archives':{},'builds':{},'comparisons':{},'started_unix':time.time()}
assert record['compiler_sha256']=='23f2e89aafe312160062cda12010ce4511366ee8131e87847a00bbce36806c89'
for variant,archive in variants.items():
 os.chmod(archive/'libms_native.a',0o444);os.chmod(archive/'ms_rt_hot.ll',0o444)
 record['archives'][variant]={p:hashlib.sha256((archive/p).read_bytes()).hexdigest() for p in ['libms_native.a','ms_rt_hot.ll']}
 assert record['archives'][variant]['ms_rt_hot.ll']=='8315efc0c1ae0b87ff80185ee282e4ede97e82afa6ecfe1825fe296549bc46ef'
 out=root/variant;out.mkdir()
 for name,folder,source,identities,pairs in suites:
  src=Path('bench/perf')/folder/source;args=[str(compiler),'build',str(src),'--build-type','Release','-o',str(out/name),'--json']
  env=os.environ.copy();env['MS_RT_LIB']=str(archive/'libms_native.a');env['MS_LLVM_TOOLS']='/workspace/.cache/ms/llvm/d19868df5ca10629'
  with (out/(name+'-build.json')).open('w') as log,(out/(name+'-build.stderr')).open('w') as err:r=subprocess.run(args,env=env,stdout=log,stderr=err)
  entry={'command':args,'exit_code':r.returncode,'source_sha256':hashlib.sha256(src.read_bytes()).hexdigest()};record['builds'][variant+'/'+name]=entry;(root/'record.json').write_text(json.dumps(record,indent=2)+'\n');print('build',variant,name,r.returncode,flush=True)
  if r.returncode:raise SystemExit(r.returncode)
  entry['program_sha256']=hashlib.sha256((out/name).read_bytes()).hexdigest();entry['public_metadata']=json.loads((out/(name+'.ms-build.json')).read_text())
for name,folder,source,identities,pairs in suites:
 identity=Path('bench/perf')/folder/identities;expected=json.loads(identity.read_text());data=root/(name+'-samples.csv');summary=root/(name+'-summary.csv')
 args=['taskset','-c','0','python3','bench/perf/string-lines/compare.py',str(root/'before'/name),str(root/'after'/name),str(data),'--pairs',str(pairs),'--identity-file',str(identity)]
 with summary.open('w') as log:r=subprocess.run(args,stdout=log)
 record['comparisons'][name]={'command':args,'exit_code':r.returncode,'cases':len(expected),'expected_rows':len(expected)*2*pairs,'identities_sha256':hashlib.sha256(identity.read_bytes()).hexdigest()};(root/'record.json').write_text(json.dumps(record,indent=2)+'\n');print('comparison',name,r.returncode,flush=True)
 if r.returncode:raise SystemExit(r.returncode)
 subprocess.run(['python3','/tmp/string-round2/analyze-pairs.py',str(data),str(identity),str(root/(name+'-')),str(pairs)],check=True)
record['finished_unix']=time.time();(root/'record.json').write_text(json.dumps(record,indent=2)+'\n')
