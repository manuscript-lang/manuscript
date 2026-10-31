from pathlib import Path
import os,json,subprocess,hashlib,time
root=Path('/tmp/string-round2/normalization-partial-revert/performance');root.mkdir()
compiler=Path('/tmp/string-round2/integrated-inputs/ms');variants={'baseline':Path('/tmp/string-round2/normalization-factorial/baseline'),'lazy':Path('/tmp/string-round2/normalization-factorial/normalize_only'),'candidate':Path('/tmp/string-round2/normalization-partial-revert')}
sources={'full':Path('bench/perf/string-normalize-ascii/main.ms'),'budget':Path('/tmp/string-round2/integration-controls/normalize-budget-confirmation-formatted.ms')}
identities={'full':Path('bench/perf/string-normalize-ascii/identities.json'),'budget':Path('/tmp/string-round2/integration-controls/normalize-budget-confirmation-identities.json')}
record={'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'native_context_main':'db975ce2f01ddf8da108ec9045ecaf66a63ab22c','variants':{},'builds':{},'comparisons':{},'started_unix':time.time()}
assert record['compiler_sha256']=='23f2e89aafe312160062cda12010ce4511366ee8131e87847a00bbce36806c89'
for variant,archive in variants.items():
 out=root/variant;out.mkdir();os.chmod(archive/'libms_native.a',0o444);os.chmod(archive/'ms_rt_hot.ll',0o444)
 record['variants'][variant]={name:hashlib.sha256((archive/name).read_bytes()).hexdigest() for name in ['libms_native.a','ms_rt_hot.ll','string.rs']};assert record['variants'][variant]['ms_rt_hot.ll']=='8315efc0c1ae0b87ff80185ee282e4ede97e82afa6ecfe1825fe296549bc46ef'
 for phase,source in sources.items():
  env=os.environ.copy();env['MS_RT_LIB']=str(archive/'libms_native.a');env['MS_LLVM_TOOLS']='/workspace/.cache/ms/llvm/d19868df5ca10629';args=[str(compiler),'build',str(source),'--build-type','Release','-o',str(out/phase),'--json']
  with (out/(phase+'-build.json')).open('w') as log,(out/(phase+'-build.stderr')).open('w') as err:r=subprocess.run(args,env=env,stdout=log,stderr=err)
  entry={'command':args,'exit_code':r.returncode,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest()};record['builds'][variant+'/'+phase]=entry;print('build',variant,phase,r.returncode,flush=True)
  if r.returncode:raise SystemExit(r.returncode)
  entry['program_sha256']=hashlib.sha256((out/phase).read_bytes()).hexdigest();entry['public_metadata']=json.loads((out/(phase+'.ms-build.json')).read_text())
(root/'record.json').write_text(json.dumps(record,indent=2)+'\n')
for phase,pairs in [('full',7),('budget',9)]:
 for reference in ['baseline','lazy']:
  name=phase+'-vs-'+reference;raw=root/(name+'-samples.csv');summary=root/(name+'-summary.csv');identity=identities[phase]
  args=['taskset','-c','0','python3','bench/perf/string-lines/compare.py',str(root/reference/phase),str(root/'candidate'/phase),str(raw),'--pairs',str(pairs),'--identity-file',str(identity)]
  with summary.open('w') as log:r=subprocess.run(args,stdout=log)
  record['comparisons'][name]={'command':args,'exit_code':r.returncode,'cases':len(json.loads(identity.read_text())),'identities_sha256':hashlib.sha256(identity.read_bytes()).hexdigest()};(root/'record.json').write_text(json.dumps(record,indent=2)+'\n');print('comparison',name,r.returncode,flush=True)
  if r.returncode:raise SystemExit(r.returncode)
  subprocess.run(['python3','/tmp/string-round2/analyze-pairs.py',str(raw),str(identity),str(root/(name+'-')),str(pairs)],check=True)
record['finished_unix']=time.time();(root/'record.json').write_text(json.dumps(record,indent=2)+'\n')
