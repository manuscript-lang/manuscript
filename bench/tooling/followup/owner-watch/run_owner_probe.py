#!/usr/bin/env python3
import argparse,hashlib,json,os,pathlib,subprocess,tempfile
p=argparse.ArgumentParser();p.add_argument('--checkout',type=pathlib.Path,required=True);p.add_argument('--commit',required=True);p.add_argument('--go',type=pathlib.Path,required=True);p.add_argument('--cache',type=pathlib.Path,required=True);p.add_argument('--output',type=pathlib.Path,required=True);p.add_argument('--iterations',type=int,default=20);p.add_argument('--count',type=int,default=5);p.add_argument('--bench',default='Benchmark(OwnerEvent|OrdinaryChange)$');a=p.parse_args();a.checkout=a.checkout.resolve();a.go=a.go.resolve();a.output.mkdir(parents=True,exist_ok=True)
def git(*args):return subprocess.check_output(['git','-C',str(a.checkout),*args])
commit=git('rev-parse',a.commit).decode().strip();package=a.checkout/'pkg/tooling/lsp'
changes=git('diff','--name-only',commit,'--','.',':(exclude)pkg/tooling/lsp').decode().splitlines()
if changes:raise SystemExit('Non-LSP sources differ from selected commit: '+repr(changes))
untracked=[name for name in git('ls-files','--others','--exclude-standard').decode().splitlines() if not name.startswith('pkg/tooling/lsp/') and (name.endswith(('.go','.ms')) or pathlib.Path(name).name in ('go.mod','go.sum'))]
if untracked:raise SystemExit('Untracked non-LSP source differs from selected commit: '+repr(untracked))
names=git('ls-tree','-r','--name-only',commit,'pkg/tooling/lsp').decode().splitlines();sources={n:git('show',f'{commit}:{n}') for n in names if n.endswith('.go')}
meta={'commit':commit,'go':subprocess.check_output([str(a.go),'version']).decode().strip(),'gomaxprocs':2,'count':a.count,'fixed_iterations_per_sample':a.iterations,'modules_per_root':4,'functions_per_module':8,'roots':[2,4,8],'source_sha256':{n:hashlib.sha256(v).hexdigest() for n,v in sources.items()},'stdlib_tree':git('rev-parse',f'{commit}:pkg/stdlib').decode().strip(),'msversion':git('show',f'{commit}:.msversion').decode().strip(),'verified_non_lsp_matches_commit':True,'scope':'in-process Go server handle including actual compile+diagnostic publication; fixture writes and fresh validation outside timer; no extension host/wire latency'}
with tempfile.TemporaryDirectory(prefix='owner-probe-') as temp:
 temp=pathlib.Path(temp);replace={}
 for path in package.glob('*.go'):
  if str(path.relative_to(a.checkout)) not in sources:
   dst=temp/path.name;dst.write_text('package lsp\n');replace[str(path)]=str(dst)
 for name,raw in sources.items():
  path=a.checkout/name;text=raw.decode()
  if not name.endswith('_test.go'):
   text=text.replace('compiler.CompileFile','ownerProbeCompile').replace('project.FindManifest','ownerProbeManifest').replace('filepath.EvalSymlinks','ownerProbeCanonical')
   if '"github.com/manuscript-lang/manuscript/pkg/project"' in text and 'project.' not in text:text+='\nvar _ = project.FindManifest\n'
  if not path.exists() or text!=path.read_text():
   dst=temp/path.name;dst.write_text(text);replace[str(path)]=str(dst)
 replace[str(package/'external_owner_probe_test.go')]=str(pathlib.Path(__file__).with_name('owner_probe_test.go.txt').resolve())
 overlay=temp/'overlay.json';overlay.write_text(json.dumps({'Replace':replace}))
 command=[str(a.go),'test','-overlay',str(overlay),'./pkg/tooling/lsp','-run','^$','-bench',a.bench,'-benchtime',str(a.iterations)+'x','-count',str(a.count),'-benchmem'];meta['command']=command
 env=dict(os.environ,GOCACHE=str(a.cache.resolve()),GOMAXPROCS='2');r=subprocess.run(command,cwd=a.checkout,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
 meta['exit_code']=r.returncode;(a.output/'raw.txt').write_text(r.stdout);(a.output/'metadata.json').write_text(json.dumps(meta,indent=2)+'\n');print(r.stdout,end='');raise SystemExit(r.returncode)
