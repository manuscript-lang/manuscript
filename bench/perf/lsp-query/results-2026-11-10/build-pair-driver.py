import os,subprocess,shutil,hashlib,json
from pathlib import Path
root=Path('/workspace/manuscript'); tools=Path('/workspace/lsp-query-tools')
nav=root/'crates/ms-lsp/src/nav.rs'; candidate=nav.read_bytes()
env=os.environ.copy();env.update(CARGO_HOME=str(tools/'cargo'),RUSTUP_HOME=str(tools/'rustup'))
command=[str(tools/'cargo/bin/cargo'),'+1.99.1','build','--release','--locked','--manifest-path','bench/perf/lsp-query/Cargo.toml','--target-dir',str(tools/'bench-target')]
evidence=root/'bench/perf/lsp-query/results-2026-11-10'
revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
meta={'revision':revision,'command':command,'variants':{}}
try:
 nav.write_bytes(subprocess.check_output(['git','show','HEAD:crates/ms-lsp/src/nav.rs'],cwd=root))
 for variant in ['before-current','after-current']:
  if variant=='after-current':nav.write_bytes(candidate)
  with (evidence/(variant+'-build.log')).open('w') as log:
   subprocess.run(command,cwd=root,env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
  target=tools/variant;target.mkdir(exist_ok=True)
  hashes={}
  for name in ['ms-lsp-query-perf','ms-lsp-server']:
   dest=target/name;shutil.copy2(tools/'bench-target/release'/name,dest)
   hashes[name]=hashlib.sha256(dest.read_bytes()).hexdigest()
  meta['variants'][variant]={'binary_sha256':hashes,'nav_sha256':hashlib.sha256(nav.read_bytes()).hexdigest()}
  print('built',variant,revision,flush=True)
finally:
 nav.write_bytes(candidate)
meta['harness_sha256']=hashlib.sha256((root/'bench/perf/lsp-query/main.rs').read_bytes()).hexdigest()
(evidence/'current-pair.json').write_text(json.dumps(meta,indent=2)+'\n')
