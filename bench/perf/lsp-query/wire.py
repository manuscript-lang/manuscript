#!/usr/bin/env python3
"""Compare exact LSP payloads and supervised process round trips, no editor UI."""
import csv
import hashlib
import json
import os
from pathlib import Path
import signal
import statistics
import subprocess
import sys
import time

before, after, output = sys.argv[1:4]
samples = int(sys.argv[4]) if len(sys.argv)>4 else 7
root = Path('/tmp/ms-lsp-query-wire-isolated')
root.mkdir(exist_ok=True)
assert not list(root.iterdir())
uri = (root/'main.ms').as_uri()
base = Path(__file__).resolve().parents[3]
fixture = (base/'crates/ms-lsp/tests/hover_documentation/source.ms').read_text()
template = (Path(__file__).parent/'function.ms').read_text()
cpu = min(os.sched_getaffinity(0))

class Lsp:
    def __init__(self, binary, source):
        self.p = subprocess.Popen(['taskset','-c',str(cpu),binary],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        self.ident = 0
        self.call('initialize', {'capabilities':{},'rootUri':root.as_uri()})
        self.send('initialized',{})
        self.send('textDocument/didOpen',{'textDocument':{'uri':uri,'languageId':'manuscript','version':1,'text':source}})
        symbols = self.call('textDocument/documentSymbol',{'textDocument':{'uri':uri}})
        assert symbols
    def send(self, method, params, ident=None):
        message = {'jsonrpc':'2.0','method':method,'params':params}
        if ident is not None: message['id']=ident
        data = json.dumps(message,ensure_ascii=False).encode()
        self.p.stdin.write(f'Content-Length: {len(data)}\r\n\r\n'.encode()+data)
        self.p.stdin.flush()
    def call(self,method,params):
        self.ident+=1
        self.send(method,params,self.ident)
        while True:
            header=self.p.stdout.readline()
            assert header, self.p.stderr.read().decode()
            size=int(header.split(b':',1)[1]);assert self.p.stdout.readline()==b'\r\n'
            value=json.loads(self.p.stdout.read(size))
            if value.get('method')=='textDocument/publishDiagnostics':
                assert not [d for d in value['params']['diagnostics'] if d['severity']==1],value
            if value.get('id')==self.ident:
                assert 'error' not in value,value
                return value['result']
    def close(self):
        self.call('shutdown',{})
        self.send('exit',{})
        self.p.stdin.close()
        assert self.p.wait(timeout=10)==0

expected={}
with Path(output).open('w') as f:
    writer=csv.writer(f)
    writer.writerow(['count','newline','query','variant','sample','rounds','elapsed_ns','sha256','setup_ns'])
    cases = [(1,'lf'),(100,'lf'),(1000,'lf'),(4000,'lf'),(1000,'crlf')]
    if os.environ.get('LSP_WIRE_CASES'):
        selected = set(os.environ['LSP_WIRE_CASES'].split(','))
        cases = [case for case in cases if ':'.join(map(str,case)) in selected]
        assert cases, selected
    for n,newline in cases:
        source=fixture+'\n'+''.join(template.replace('item_N',f'item_{i}')+'\n' for i in range(n))
        if newline=='crlf':source=source.replace('\n','\r\n')
        targets=[('local-first','value +',False,'value: Int'),('local-last','value +',True,'value: Int'),('literal','123',True,'123: Int'),('function','documented(meter',False,'Function documentation.'),('method','read() +',False,'Method documentation.'),('receiver','plain())',False,'Receiver documentation.'),('unicode','value}',False,'value: Int')]
        if os.environ.get('LSP_WIRE_QUERIES'):
            selected = set(os.environ['LSP_WIRE_QUERIES'].split(','))
            targets = [target for target in targets if target[0] in selected]
            assert targets, selected
        for sample in range(samples):
            for variant,binary in ([('before',before),('after',after)] if sample%2==0 else [('after',after),('before',before)]):
                signal.alarm(120)
                start=time.perf_counter_ns();client=Lsp(binary,source);setup=time.perf_counter_ns()-start
                try:
                    for label,needle,last,contains in targets:
                        offset=source.rfind(needle) if last else source.find(needle)
                        prefix=source[:offset];line=prefix.count('\n');column=len(prefix.rsplit('\n',1)[-1].encode('utf-16-le'))//2
                        args={'textDocument':{'uri':uri},'position':{'line':line,'character':column}}
                        result=client.call('textDocument/hover',args)
                        assert contains in result['contents']['value'],result
                        key=(n,newline,label)
                        if key not in expected:expected[key]=result
                        assert result==expected[key],(key,variant,result,expected[key])
                        for _ in range(3):assert client.call('textDocument/hover',args)==result
                        rounds=int(os.environ.get("LSP_WIRE_ROUNDS", "30"))
                        start=time.perf_counter_ns()
                        results=[client.call('textDocument/hover',args) for _ in range(rounds)]
                        elapsed=time.perf_counter_ns()-start
                        assert all(r==result for r in results)
                        digest=hashlib.sha256(json.dumps(result,sort_keys=True,ensure_ascii=False).encode()).hexdigest()
                        writer.writerow([n,newline,label,variant,sample,rounds,elapsed,digest,setup]);f.flush()
                finally:
                    client.close();signal.alarm(0)
        print('completed',n,newline,flush=True)
Path(output).with_suffix('.payloads.json').write_text(json.dumps({str(k):v for k,v in expected.items()},ensure_ascii=False,indent=2)+'\n')
