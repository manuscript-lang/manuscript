#!/usr/bin/env python3
import argparse,hashlib,json,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--repo',required=True);p.add_argument('--out',required=True);p.add_argument('--candidate',action='store_true');a=p.parse_args()
base=pathlib.Path(__file__).resolve().parent;repo=pathlib.Path(a.repo).resolve();out=pathlib.Path(a.out).resolve();out.mkdir(parents=True,exist_ok=True)
replace={}
for src,target in [('index_probe_test.go.txt','pkg/tooling/lsp/lexical_index_probe_test.go'),('candidate_adapter.go.txt' if a.candidate else 'baseline_adapter.go.txt','pkg/tooling/lsp/lexical_inventory_adapter_test.go')]:
 dest=out/src;dest.write_bytes((base/src).read_bytes());replace[str(repo/target)]=str(dest)
(out/'overlay.json').write_text(json.dumps({'Replace':replace},indent=2)+'\n')
patch=subprocess.check_output(['git','diff','--binary','HEAD'],cwd=repo);(out/'working-tree.patch').write_bytes(patch)
metadata={'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),'working_diff_sha256':hashlib.sha256(patch).hexdigest(),'repo':str(repo),'candidate':a.candidate,'probe_sha256':hashlib.sha256((base/'index_probe_test.go.txt').read_bytes()).hexdigest(),'adapter_sha256':hashlib.sha256((base/('candidate_adapter.go.txt' if a.candidate else 'baseline_adapter.go.txt')).read_bytes()).hexdigest()}
(out/'inputs.json').write_text(json.dumps(metadata,indent=2)+'\n');print(out/'overlay.json')
