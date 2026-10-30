from pathlib import Path
import subprocess,hashlib,json,os,time
root=Path('/tmp/string-round2/normalization-full-revert'); checks=root/'checks'; inputs=root/'inputs';record=json.loads((root/'record.json').read_text());p=Path('crates/ms-rt/src/string.rs');after=p.read_bytes()
assert hashlib.sha256(after).hexdigest()=='d9124ee3a902263ee12b9daa6668dab4e6609044e40e72c5074c167e1be4a2c0'
assert record['checks']['performance']['exit_code']==0
assert not (checks/'conform.log').exists()
assert record['input_hashes']=={x.name:hashlib.sha256(x.read_bytes()).hexdigest() for x in inputs.iterdir()}
env=os.environ.copy();env['MS_RT_LIB']=str(inputs/'libms_native.a');env['MS_LLVM_TOOLS']='/workspace/.cache/ms/llvm/d19868df5ca10629'
def save(): (root/'record.json').write_text(json.dumps(record,indent=2)+'\n')
def run(name,args,env=None):
 with (checks/(name+'.log')).open('w') as log:r=subprocess.run(args,env=env,stdout=log,stderr=subprocess.STDOUT)
 record['checks'][name]={'command':args,'exit_code':r.returncode};save();print(name,r.returncode,flush=True)
 if r.returncode:raise SystemExit(r.returncode)
record['continuation_note']='Original exec session unavailable after context transition; filesystem record confirms all through performance exited0. No conformance log existed. Resume only analysis and never-started conformance; no completed run overwritten.';save()
subprocess.run(['python3','/tmp/string-round2/analyze-pairs.py',str(root/'performance/samples.csv'),'bench/perf/string-normalize-ascii/identities.json',str(root/'performance')+'/','7'],check=True)
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
