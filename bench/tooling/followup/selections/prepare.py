#!/usr/bin/env python3
"""Create read-only Go overlay instrumentation; never edits the checkout."""
import argparse, hashlib, json, pathlib, subprocess
p=argparse.ArgumentParser(); p.add_argument('--repo',default='/workspace/manuscript-tooling-followup'); p.add_argument('--out',required=True); a=p.parse_args()
repo=pathlib.Path(a.repo).resolve(); out=pathlib.Path(a.out).resolve(); out.mkdir(parents=True,exist_ok=True)
base=pathlib.Path(__file__).resolve().parent
replace={}; inputs={}
def put(target,text):
    dest=out/target.replace('/','__'); dest.write_text(text); replace[str(repo/target)]=str(dest)
for path,needle,extra in [
('pkg/compiler/compiler.go','func CompileFile(filename string, options Options) Result {','\n\tif FollowupCompileObserver != nil { FollowupCompileObserver(filename, options) }'),
('pkg/lexer/lexer.go','func Lex(file, source string) (tokens []Token, err error) {','\n\tif FollowupLexObserver != nil { FollowupLexObserver(file, source) }'),
('pkg/tooling/lsp/index.go','func sourceIndex(result compiler.Result) []occurrence {','\n\tif followupIndexObserver != nil { followupIndexObserver(result) }')]:
    text=(repo/path).read_text(); inputs[path]=hashlib.sha256(text.encode()).hexdigest()
    assert text.count(needle)==1, (path,'instrumentation anchor changed')
    put(path,text.replace(needle,needle+extra,1))
put('pkg/compiler/followup_probe_hooks.go','package compiler\nvar FollowupCompileObserver func(string, Options)\n')
put('pkg/lexer/followup_probe_hooks.go','package lexer\nvar FollowupLexObserver func(string, string)\n')
put('pkg/tooling/lsp/followup_probe_hooks.go','package lsp\nimport "github.com/manuscript-lang/manuscript/pkg/compiler"\nvar followupIndexObserver func(compiler.Result)\n')
put('pkg/tooling/lsp/followup_measurement_test.go',(base/'probe_test.go.txt').read_text())
(out/'overlay.json').write_text(json.dumps({'Replace':replace},indent=2)+'\n')
patch=subprocess.check_output(['git','diff','--binary','HEAD'],cwd=repo)
(out/'working-tree.patch').write_bytes(patch)
metadata={'working_diff_sha256':hashlib.sha256(patch).hexdigest(),'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),'diff':subprocess.check_output(['git','diff','--stat'],cwd=repo,text=True),'source_sha256':inputs,'probe_sha256':hashlib.sha256((base/'probe_test.go.txt').read_bytes()).hexdigest(),'repo':str(repo)}
(out/'inputs.json').write_text(json.dumps(metadata,indent=2)+'\n')
print(out/'overlay.json')
