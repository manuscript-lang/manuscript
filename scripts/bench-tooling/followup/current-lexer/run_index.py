#!/usr/bin/env python3
import argparse,json,os,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--repo',required=True);p.add_argument('--label',required=True);p.add_argument('--candidate',action='store_true');p.add_argument('--modules',default='41,101');p.add_argument('--library',action='store_true');p.add_argument('--cold-processes',type=int,default=5);p.add_argument('--warm-count',type=int,default=5);p.add_argument('--benchtime',default='500ms');a=p.parse_args()
base=pathlib.Path(__file__).resolve().parent;out=base/a.label;repo=pathlib.Path(a.repo).resolve();out.mkdir(parents=True,exist_ok=True)
cmd=['python3',str(base/'prepare_index.py'),'--repo',str(repo),'--out',str(out)]+(['--candidate'] if a.candidate else []);subprocess.run(cmd,check=True)
env={**os.environ,'GOCACHE':os.environ.get('GOCACHE','/tmp/manuscript-tooling-go-cache'),'GOMAXPROCS':'4','GOGC':'100','GOMEMLIMIT':'off'}
with (out/'build.log').open('w') as log:subprocess.run([str(repo/'toolchain/go/bin/go'),'test','-c','-overlay='+str(out/'overlay.json'),'-o',str(out/'probe.test'),'./pkg/tooling/lsp'],cwd=repo,env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
records=[]
done=subprocess.run([str(out/'probe.test'),'-test.run=^TestLexicalPinnedTokenInventory$','-test.v'],cwd=repo,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);(out/'token-inventory.log').write_text(done.stdout)
if done.returncode:raise SystemExit('token inventory failed: '+done.stdout[-2000:])
for n in map(int,a.modules.split(',')):
 case=f'{"library" if a.library else "app"}-{n}'
 runenv={**env,'LEXICAL_MODULES':str(n),'LEXICAL_LIBRARY':str(int(a.library))}
 for payload_sample in range(2):
  directory=out/'payloads'/case/f'payload-{payload_sample}'
  done=subprocess.run([str(out/'probe.test'),'-test.run=^TestLexical(SourceIndexPayload|SerializerCoversInfo)$','-test.v'],cwd=repo,env={**runenv,'LEXICAL_PAYLOAD_DIR':str(directory)},text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);(out/f'{case}-payload-{payload_sample}.log').write_text(done.stdout)
  if done.returncode:raise SystemExit('payload probe failed: '+done.stdout[-2000:])
 for sample in range(a.cold_processes):
  directory=out/'payloads'/case/f'cold-{sample}';e={**runenv,'LEXICAL_PAYLOAD_DIR':str(directory)}
  done=subprocess.run([str(out/'probe.test'),'-test.run=^TestLexical(ColdIndex|SerializerCoversInfo)$','-test.v'],cwd=repo,env=e,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);(out/f'{case}-cold-{sample}.log').write_text(done.stdout)
  if done.returncode:raise SystemExit('cold probe failed: '+done.stdout[-2000:])
  for line in done.stdout.splitlines():
   if 'lexical_cold=' in line:records.append({'case':case,'sample':sample,**json.loads(line.split('lexical_cold=',1)[1])})
 done=subprocess.run([str(out/'probe.test'),'-test.run=^$','-test.bench=^BenchmarkLexicalSourceIndex$','-test.benchmem','-test.benchtime='+a.benchtime,'-test.count='+str(a.warm_count),'-test.v'],cwd=repo,env=runenv,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);(out/f'{case}-warm.log').write_text(done.stdout)
 if done.returncode:raise SystemExit('warm benchmark failed: '+done.stdout[-2000:])
 print('passed '+case,flush=True)
(out/'cold.json').write_text(json.dumps(records,indent=2)+'\n');print(out/'cold.json')
