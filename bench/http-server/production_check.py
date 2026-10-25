import base64,hashlib,http.client,json,os,socket,subprocess,time
TOKEN='integration-test-secret-only'
results=[]
for mode,port in [('workers',19811),('processes',19812)]:
 log=open('/tmp/http-production-'+mode+'.log','w')
 child=subprocess.Popen(['/tmp/manuscript-production-example',mode,'2',f'127.0.0.1:{port}'],env={**os.environ,'API_TOKEN':TOKEN},stdout=log,stderr=log)
 def request(method,path,data=None,auth=True):
  c=http.client.HTTPConnection('127.0.0.1',port,timeout=10)
  try:
   h={'Content-Type':'application/json'}
   if auth:h['Authorization']='Bearer '+TOKEN
   c.request(method,path,data,h);r=c.getresponse();return r.status,r.read()
  finally:c.close()
 try:
  for _ in range(200):
   if child.poll() is not None:raise RuntimeError('startup exited')
   try:
    if request('GET','/ready')[0]==200:break
   except OSError:pass
   time.sleep(.05)
  else:raise RuntimeError('startup timeout')
  assert request('GET','/health',auth=False)==(200,b'ok')
  assert request('POST','/api/greeting','{"name":"Ada"}',auth=False)[0]==401
  seen=set()
  for _ in range(20):
   status,body=request('POST','/api/greeting','{"name":"Ada"}');value=json.loads(body);assert status==200 and value['message']=='Hello, Ada';seen.add(value['member'])
  assert request('POST','/api/greeting','{')[0]==400
  assert request('POST','/api/greeting','{"name":""}')[0]==422
  status,body=request('GET','/api/events');assert status==200 and body.count(b'event: tick')==5
  with socket.create_connection(('127.0.0.1',port),timeout=5) as s:
   key=base64.b64encode(b'0123456789abcdef').decode()
   s.sendall(f'GET /api/socket HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nAuthorization: Bearer {TOKEN}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n'.encode())
   head=b''
   while not head.endswith(b'\r\n\r\n'):head+=s.recv(1)
   assert head.startswith(b'HTTP/1.1 101'),head
   expected=base64.b64encode(hashlib.sha1((key+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest())
   assert expected in head
   payload=b'hello';mask=b'abcd';s.sendall(bytes([0x81,0x80|len(payload)])+mask+bytes(x^mask[i%4] for i,x in enumerate(payload)))
   reply=b''
   while len(reply)<7:reply+=s.recv(7-len(reply))
   assert reply==b'\x81\x05hello',reply
  status,body=request('GET','/api/stats');stats=json.loads(body);assert status==200 and stats['requests']>=1 and stats['completed']<=stats['requests']
  results.append({'mode':mode,'members':sorted(seen),'health':True,'auth':True,'json':True,'sse':True,'websocket':True,'observations':True})
 finally:
  child.terminate()
  try:child.wait(timeout=15)
  except subprocess.TimeoutExpired:child.kill();child.wait();raise
  log.close()
print(json.dumps(results))
open('/tmp/http-production-results.json','w').write(json.dumps(results,indent=2)+'\n')
