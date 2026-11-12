import sys,subprocess,itertools,json,hashlib
from pathlib import Path
p=Path(sys.argv[1]).resolve();cases=[]
for lead,mid,tail,words in itertools.product(['','\n','\n\n'],['\n','\n\n','\n\n\n','\r\n  \r\n'],['','\n','\n\n'],[('alpha','beta'),('日付','🙂'),('true','false')]):
 cases.append('['+lead+' '+words[0]+mid+' '+words[1]+tail+']')
cases += ['[alpha\n: beta]','[alpha\n---\n beta]','[alpha\n beta','[alpha\n #comment\n beta]','[a\n \t b]']
for i in range(0,len(cases),30):
 args=cases[i:i+30];a=subprocess.run([str(p/'check-base'),*args],capture_output=True,check=True);b=subprocess.run([str(p/'check-new'),*args],capture_output=True,check=True);assert a.stdout==b.stdout and a.stderr==b.stderr,(i,a.stdout,b.stdout)
(p/'differential.json').write_text(json.dumps({'cases':cases,'matched':len(cases)},indent=2));print(len(cases),'matched exact outputs/errors')
