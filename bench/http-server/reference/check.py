#!/usr/bin/env python3
"""Executable common HTTP contract; narrow evidence, not complete framework equivalence."""
import concurrent.futures
import http.client
import json
import os
import pathlib
import subprocess
import time

ROOT=pathlib.Path(__file__).resolve().parent

def call(port,method,path,body=None):
    connection=http.client.HTTPConnection('127.0.0.1',port,timeout=5)
    try:
        connection.request(method,path,body,{'Content-Type':'application/json'})
        response=connection.getresponse()
        return response.status,dict(response.getheaders()),response.read()
    finally: connection.close()


def check(name,command,port,cwd=ROOT):
    log=open('/tmp/http-reference-'+name+'.log','w')
    env={**os.environ,'PORT':str(port),'NEXT_TELEMETRY_DISABLED':'1'}
    process=subprocess.Popen(command,cwd=cwd,env=env,stdout=log,stderr=log)
    observations=[]
    try:
        for _ in range(300):
            if process.poll() is not None: raise RuntimeError(f'{name} exited during startup')
            try: call(port,'GET','/'); break
            except OSError: time.sleep(.1)
        else: raise RuntimeError(f'{name} startup timed out')
        for method,path,body,status,expected in [
            ('GET','/hello/Ada',None,200,{'message':'Hello, Ada'}),
            ('POST','/echo','{"name":"Ada"}',200,{'message':'Hello, Ada'}),
            ('POST','/echo','{',400,None),
            ('POST','/echo','{"name":"Ada","unexpected":true}',400,None),
            ('HEAD','/hello/Ada',None,200,None),
            ('GET','/missing',None,404,None),
            ('GET','/events',None,200,None),
            ('GET','/',None,200,None),
        ]:
            actual,headers,payload=call(port,method,path,body)
            assert actual==status,(name,method,path,actual,status)
            lower={key.lower():value for key,value in headers.items()}
            assert lower.get('x-example')=='reference',(name,'middleware')
            if expected is not None: assert json.loads(payload)==expected,(name,payload)
            if method=='HEAD': assert payload==b''
            if path=='/events': assert payload==b'data: one\n\ndata: two\n\n'
            if path=='/': assert b'<h1>Hello</h1>' in payload
            observations.append({'method':method,'path':path,'status':actual,'bytes':len(payload)})
        with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
            results=list(pool.map(lambda _:call(port,'GET','/hello/Ada'),range(64)))
        assert all(status==200 for status,_,_ in results)
        return {'name':name,'cases':observations,'concurrent_requests':len(results),'passed':True}
    finally:
        process.terminate()
        try: process.wait(timeout=10)
        except subprocess.TimeoutExpired: process.kill();process.wait()
        log.close()

if __name__=='__main__':
    results=[]
    for args in [('node',['node','node.mjs'],19801),('express',['node','express.mjs'],19802),('go',['/tmp/manuscript-http-go-reference'],19803),('next',['../node_modules/.bin/next','start','-p','19804','-H','127.0.0.1'],19804,ROOT/'next'),('manuscript',['/tmp/manuscript-http-reference'],19805)]:
        result=check(*args);results.append(result);print(json.dumps(result),flush=True)
    pathlib.Path('/tmp/http-reference-results.json').write_text(json.dumps({'references':{'node':'24.19.0','express':'5.1.0','go':'1.25.1','next':'16.0.10','react':'19.2.3'},'results':results},indent=2)+'\n')
