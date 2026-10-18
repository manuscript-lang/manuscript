#!/usr/bin/env python3
"""Read-only source overlay. Pins every LSP Go file to --commit; no checkout edits."""
import argparse,hashlib,json,os,pathlib,subprocess,tempfile
p=argparse.ArgumentParser();p.add_argument('--checkout',type=pathlib.Path,required=True);p.add_argument('--commit',required=True);p.add_argument('--go',type=pathlib.Path,required=True);p.add_argument('--cache',type=pathlib.Path,required=True);p.add_argument('--case',choices=['work','read-error'],required=True);p.add_argument('--output',type=pathlib.Path,required=True);p.add_argument('--mutation',choices=['canonical-key-only','drop-overlay-text','drop-ambiguous-suppression']);p.add_argument('--test');a=p.parse_args()
a.checkout=a.checkout.resolve();a.go=a.go.resolve();a.output.mkdir(parents=True,exist_ok=True)
def git(*args):return subprocess.check_output(['git','-C',str(a.checkout),*args])
commit=git('rev-parse',a.commit).decode().strip();package=a.checkout/'pkg/tooling/lsp'
non_lsp_changes=git('diff','--name-only',commit,'--','.',':(exclude)pkg/tooling/lsp').decode().splitlines()
untracked=[name for name in git('ls-files','--others','--exclude-standard').decode().splitlines() if not name.startswith('pkg/tooling/lsp/') and (name.endswith(('.go','.ms')) or pathlib.Path(name).name in ('go.mod','go.sum'))]
if non_lsp_changes or untracked:raise SystemExit('Non-LSP checkout differs from selected commit; use a compatible isolated checkout: '+repr(non_lsp_changes+untracked))
files=git('ls-tree','-r','--name-only',commit,'pkg/tooling/lsp').decode().splitlines();sources={name:git('show',f'{commit}:{name}') for name in files if name.endswith('.go')}
metadata={'commit':commit,'case':a.case,'mutation':a.mutation,'go':subprocess.check_output([str(a.go),'version']).decode().strip(),'gomaxprocs':2,'samples_per_size_and_order':5 if a.case=='work' else 1,'go_pin':git('show',f'{commit}:.go-version').decode().strip(),'stdlib_tree':git('rev-parse',f'{commit}:pkg/stdlib').decode().strip(),'msversion':git('show',f'{commit}:.msversion').decode().strip(),'source_sha256':{k:hashlib.sha256(v).hexdigest() for k,v in sources.items()},'verified_non_lsp_matches_commit':True,'scope':'counts only in LSP filesystem discovery; excludes compiler and project filesystem operations; no extension-host latency measurement'}
with tempfile.TemporaryDirectory(prefix='discovery-overlay-') as temp:
 temp=pathlib.Path(temp);replace={}
 # Hide later uncommitted Go additions while testing this immutable source.
 for path in package.glob('*.go'):
  name=str(path.relative_to(a.checkout))
  if name not in sources:
   target=temp/path.name;target.write_text('package lsp\n');replace[str(path)]=str(target)
 for name,raw in sources.items():
  text=raw.decode();path=a.checkout/name
  if pathlib.Path(name).name=='discovery.go':
   if a.mutation=='canonical-key-only':text=text.replace('key := discoveryScope{root, recursive}', 'identity := root\nif canonical, err := filepath.EvalSymlinks(root); err == nil { identity = canonical }\nkey := discoveryScope{identity, recursive}').replace('w.disk(root, recursive, canceled)','w.disk(writtenRoot, recursive, canceled)')
   if a.mutation=='drop-overlay-text':text=text.replace('text, overlaid := texts[physical]', 'text, overlaid := \"\", false')
   if a.mutation=='drop-ambiguous-suppression':text=text.replace('represented[written] || ambiguous[physical]','represented[written]')
  if pathlib.Path(name).name in ('workspace.go','discovery.go'):
   text=text.replace('os.ReadFile(', 'discoveryProbeReadFile(')
   if a.case=='work':text=text.replace('filepath.WalkDir(', 'discoveryProbeWalkDir(')
  if not path.exists() or text!=path.read_text():
   target=temp/path.name;target.write_text(text);replace[str(path)]=str(target)
 probe=pathlib.Path(__file__).with_name('work_probe_test.go.txt' if a.case=='work' else 'read_error_probe_test.go.txt')
 replace[str(package/'external_discovery_probe_test.go')]=str(probe.resolve());overlay=temp/'overlay.json';overlay.write_text(json.dumps({'Replace':replace}))
 pattern=a.test or ('TestDiscoveryPhysicalWork' if a.case=='work' else 'TestDiscoveryAuthoritativeOverlaySurvivesDiskReadFailure')
 command=[str(a.go),'test','-overlay',str(overlay),'./pkg/tooling/lsp','-run',pattern,'-v','-count=1'];metadata['command']=command
 env=dict(os.environ,GOCACHE=str(a.cache.resolve()),GOMAXPROCS='2');r=subprocess.run(command,cwd=a.checkout,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
 metadata['exit_code']=r.returncode;(a.output/'raw.txt').write_text(r.stdout);(a.output/'metadata.json').write_text(json.dumps(metadata,indent=2)+'\n');print(r.stdout,end='');raise SystemExit(r.returncode)
