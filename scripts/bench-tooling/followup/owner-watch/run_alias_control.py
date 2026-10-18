#!/usr/bin/env python3
"""Reproduce known-bad owner cache behavior from immutable LSP sources."""
import argparse,hashlib,json,os,pathlib,subprocess,tempfile
p=argparse.ArgumentParser();p.add_argument('--checkout',type=pathlib.Path,required=True);p.add_argument('--commit',required=True);p.add_argument('--go',type=pathlib.Path,required=True);p.add_argument('--cache',type=pathlib.Path,required=True);p.add_argument('--output',type=pathlib.Path,required=True);p.add_argument('--case',choices=['closed','open'],required=True);a=p.parse_args();a.checkout=a.checkout.resolve();a.go=a.go.resolve();a.output.mkdir(parents=True,exist_ok=True)
def git(*args):return subprocess.check_output(['git','-C',str(a.checkout),*args])
commit=git('rev-parse',a.commit).decode().strip();package=a.checkout/'pkg/tooling/lsp'
changed=git('diff','--name-only',commit,'--','.',':(exclude)pkg/tooling/lsp').decode().splitlines()
if changed:raise SystemExit('Non-LSP source mismatch: '+repr(changed))
untracked=[name for name in git('ls-files','--others','--exclude-standard').decode().splitlines() if not name.startswith('pkg/tooling/lsp/') and (name.endswith(('.go','.ms')) or pathlib.Path(name).name in ('go.mod','go.sum'))]
if untracked:raise SystemExit('Untracked non-LSP source differs from selected commit: '+repr(untracked))
files=git('ls-tree','-r','--name-only',commit,'pkg/tooling/lsp').decode().splitlines();sources={name:git('show',f'{commit}:{name}') for name in files if name.endswith('.go')}
base=pathlib.Path(__file__).resolve().parent
probe=base/'closed-routes/probe_test.go.txt' if a.case=='closed' else base/'overlay_footprint_probe_test.go.txt'
meta={'commit':commit,'case':a.case,'go':subprocess.check_output([str(a.go),'version']).decode().strip(),'gomaxprocs':2,'stdlib_tree':git('rev-parse',f'{commit}:pkg/stdlib').decode().strip(),'msversion':git('show',f'{commit}:.msversion').decode().strip(),'verified_non_lsp_matches_commit':True,'probe_sha256':hashlib.sha256(probe.read_bytes()).hexdigest(),'source_sha256':{name:hashlib.sha256(raw).hexdigest() for name,raw in sources.items()},'expected':'closed observation test PASS means stale cached success versus fresh failure reproduced; open correctness test FAIL means stale cached failure versus fresh success reproduced'}
with tempfile.TemporaryDirectory(prefix='owner-alias-control-') as temp:
 temp=pathlib.Path(temp);replace={}
 for path in package.glob('*.go'):
  if str(path.relative_to(a.checkout)) not in sources:
   target=temp/path.name;target.write_text('package lsp\n');replace[str(path)]=str(target)
 for name,raw in sources.items():
  path=a.checkout/name
  if not path.exists() or path.read_bytes()!=raw:
   target=temp/path.name;target.write_bytes(raw);replace[str(path)]=str(target)
 replace[str(package/'external_owner_alias_control_test.go')]=str(probe)
 overlay=temp/'overlay.json';overlay.write_text(json.dumps({'Replace':replace}))
 pattern='TestReviewClosedLexicalAliasOutsideOwner' if a.case=='closed' else 'TestWatchCrossOwnerOverlayFootprints'
 command=[str(a.go),'test','-overlay',str(overlay),'./pkg/tooling/lsp','-run',pattern,'-v','-count=1'];meta['command']=command
 result=subprocess.run(command,cwd=a.checkout,env=dict(os.environ,GOCACHE=str(a.cache.resolve()),GOMAXPROCS='2'),stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
 meta['exit_code']=result.returncode;(a.output/'raw.txt').write_text(result.stdout);(a.output/'metadata.json').write_text(json.dumps(meta,indent=2)+'\n');print(result.stdout,end='');raise SystemExit(result.returncode)
