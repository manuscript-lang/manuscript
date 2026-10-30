from pathlib import Path
import subprocess,hashlib,json,shutil,os,signal,time
root=Path('/tmp/string-round2/normalization-full-revert');root.mkdir();checks=root/'checks';checks.mkdir()
p=Path('crates/ms-rt/src/string.rs');after=p.read_bytes();before=subprocess.check_output(['git','show','HEAD:crates/ms-rt/src/string.rs']);assert hashlib.sha256(after).hexdigest()=='d9124ee3a902263ee12b9daa6668dab4e6609044e40e72c5074c167e1be4a2c0'
record={'head':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'scope':'Only normalize_kind exact baseline implementation restored; tests/evidence retained. Normal current-main builds; no compiler/backend investigation.','checks':{},'native':{},'started_unix':time.time()}
def save(): (root/'record.json').write_text(json.dumps(record,indent=2)+'\n')
def run(name,args,env=None):
 with (checks/(name+'.log')).open('w') as log:r=subprocess.run(args,env=env,stdout=log,stderr=subprocess.STDOUT)
 record['checks'][name]={'command':args,'exit_code':r.returncode};save();print(name,r.returncode,flush=True)
 if r.returncode:raise SystemExit(r.returncode)
def snap(name,source):
 out=root/name;out.mkdir();(out/'string.rs').write_bytes(source);entry={'source_sha256':hashlib.sha256(source).hexdigest()}
 for path,target in [('target/ms-native/libms_native.a','libms_native.a'),('target/ms-native/ms_rt_hot.ll','ms_rt_hot.ll')]:
  shutil.copyfile(path,out/target);os.chmod(out/target,0o444);entry[target]=hashlib.sha256((out/target).read_bytes()).hexdigest()
 record['native'][name]=entry;save()
def stop(sig,frame):raise KeyboardInterrupt(sig)
signal.signal(signal.SIGTERM,stop)
try:
 p.write_bytes(before);run('native-before',['cargo','xtask','runtime']);snap('before',before)
finally:p.write_bytes(after)
run('native-after',['cargo','xtask','runtime']);snap('after',after)
assert record['native']['before']['ms_rt_hot.ll']==record['native']['after']['ms_rt_hot.ll']
run('fmt',['cargo','fmt','--all','--','--check'])
run('string-tests',['cargo','test','--locked','-p','ms-rt','string::tests::','--','--test-threads=1'])
run('clippy',['cargo','clippy','--workspace','--all-targets','--locked','--','-D','warnings'])
run('compiler-harness-build',['cargo','build','--release','--locked','-p','ms-cli','-p','ms-conform'])
run('repo-check',['make','repo-check'])
inputs=root/'inputs';inputs.mkdir()
for source,name,mode in [('target/release/ms','ms',0o555),('target/release/ms-conform','ms-conform',0o555),(str(root/'after/libms_native.a'),'libms_native.a',0o444),(str(root/'after/ms_rt_hot.ll'),'ms_rt_hot.ll',0o444)]:
 shutil.copyfile(source,inputs/name);os.chmod(inputs/name,mode)
expect=Path('tests/conformance/expect-fail.txt').read_bytes();linux=Path('tests/conformance/expect-fail.linux.txt')
if linux.exists():expect+=linux.read_bytes()
(inputs/'expect-fail.txt').write_bytes(expect);os.chmod(inputs/'expect-fail.txt',0o444);os.chmod(inputs,0o555)
env=os.environ.copy();env['MS_RT_LIB']=str(inputs/'libms_native.a');env['MS_LLVM_TOOLS']='/workspace/.cache/ms/llvm/d19868df5ca10629';record['input_hashes']={x.name:hashlib.sha256(x.read_bytes()).hexdigest() for x in inputs.iterdir()};save()
for profile in ['Release','Debug']:
 for fixture in ['string-normalize-stream','string-normalize-ascii','typed-normalization']:
  run(fixture+'-'+profile,[str(inputs/'ms'),'test','tests/e2e/testdata/stdlib/'+fixture+'.ms','--build-type',profile],env)
performance=root/'performance';performance.mkdir();src=Path('bench/perf/string-normalize-ascii/main.ms');ids=Path('bench/perf/string-normalize-ascii/identities.json')
for variant in ['before','after']:
 out=performance/variant;out.mkdir();e=env.copy();e['MS_RT_LIB']=str(root/variant/'libms_native.a');args=[str(inputs/'ms'),'build',str(src),'--build-type','Release','-o',str(out/'program'),'--json']
 with (out/'build.json').open('w') as log,(out/'build.stderr').open('w') as err:r=subprocess.run(args,env=e,stdout=log,stderr=err)
 record['checks']['performance-build-'+variant]={'command':args,'exit_code':r.returncode};save();print('performance-build-'+variant,r.returncode,flush=True)
 if r.returncode:raise SystemExit(r.returncode)
 record.setdefault('programs',{})[variant]={'sha256':hashlib.sha256((out/'program').read_bytes()).hexdigest(),'source_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'public_metadata':json.loads((out/'program.ms-build.json').read_text())}
args=['taskset','-c','0','python3','bench/perf/string-lines/compare.py',str(performance/'before/program'),str(performance/'after/program'),str(performance/'samples.csv'),'--pairs','7','--identity-file',str(ids)]
with (performance/'summary.csv').open('w') as log:r=subprocess.run(args,stdout=log)
record['checks']['performance']={'command':args,'exit_code':r.returncode};save();print('performance',r.returncode,flush=True)
if r.returncode:raise SystemExit(r.returncode)
subprocess.run(['python3','/tmp/string-round2/analyze-pairs.py',str(performance/'samples.csv'),str(ids),str(performance)+'/','7'],check=True)
def inventory():return {x.name:{'sha256':hashlib.sha256(x.read_bytes()).hexdigest(),'size':x.stat().st_size,'mode':oct(x.stat().st_mode&0o777)} for x in sorted(inputs.iterdir())}
proof={'before':inventory(),'directory_mode':oct(inputs.stat().st_mode&0o777),'writer_coordination':'All builds and timing finished; selected dedicated read-only snapshots never a build destination; root sole gate executor; no native jobs during this replay.'};(checks/'conform-input-integrity.json').write_text(json.dumps(proof,indent=2)+'\n')
run('corpus-lint',[str(inputs/'ms-conform'),'lint'],env)
args=[str(inputs/'ms-conform'),'run','--ms',str(inputs/'ms'),'--phase','run,check,test','--exclude-tag','aliasing','--expect-fail',str(inputs/'expect-fail.txt'),'--strict','--shard','0/1','--quiet','--markdown',str(checks/'conform-report.md'),'--json',str(checks/'conform-report.json')]
with (checks/'conform.log').open('w') as log:r=subprocess.run(args,env=env,stdout=log,stderr=subprocess.STDOUT)
proof.update({'command':args,'exit_code':r.returncode,'after':inventory()});proof['hashes_match']=proof['before']==proof['after'];(checks/'conform-input-integrity.json').write_text(json.dumps(proof,indent=2)+'\n');record['checks']['conform']={'command':args,'exit_code':r.returncode,'hashes_match':proof['hashes_match']};save();print('conform',r.returncode,'hashes_match',proof['hashes_match'],flush=True)
if r.returncode:raise SystemExit(r.returncode)
if not proof['hashes_match']:raise SystemExit(99)
assert p.read_bytes()==after
record['finished_unix']=time.time();save()
