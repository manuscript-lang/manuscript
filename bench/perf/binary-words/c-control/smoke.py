import json,struct,subprocess,argparse
from pathlib import Path
P=Path(__file__).resolve().parent;D=P/'smoke';D.mkdir(exist_ok=True);records=[]
parser=argparse.ArgumentParser();parser.add_argument('--binary',type=Path,default=P/'probe');parser.add_argument('--output',type=Path,default=P/'smoke.json');args=parser.parse_args()
T=['i8','u8']+[k+end for k in ['i16','u16','i32','u32','i64','u64','f32','f64'] for end in ['le','be']]
def run(op,t,data,want,expected,start=0,fields=3,kind='OK'):
 i=D/'input';o=D/'expected';i.write_bytes(data);o.write_bytes(expected)
 cmd=[str(args.binary),op,t,str(i),str(o),str(start),str(fields),'2',want,kind]
 r=subprocess.run(cmd,text=True,capture_output=True,check=True);n,ns,c,w=map(int,r.stdout.split(','));unit=fields if op=='read' else len(expected)+1;assert n==2 and c==2*unit and w==unit
 records.append(dict(command=cmd,stdout=r.stdout,expected_message=("binary: out of range" if t.startswith("u64") else "binary: value out of range") if kind=="ERANGE" else ""))
for t in T:
 width=1 if t in ['i8','u8'] else int(t[1:3])//8;order='big' if t.endswith('be') else 'little'
 vals=[1.5] if t[0]=='f' else [0,1,(1<<(width*8-1))-1,-1,-(1<<(width*8-1))] if t[0]=='i' else [0,1,(1<<(width*8))-1]
 for v in vals:
  if t[0]=='f':b=struct.pack(('>' if order=='big' else '<')+('f' if width==4 else 'd'),v);want=str(v)
  else:b=v.to_bytes(width,order,signed=t[0]=='i');want=f'{v>>32}:{v&0xffffffff}' if t.startswith('u64') else str(v)
  run('read',t,b'!'+b*3,want,b'',start=1)
  run('pack',t,b'',want,b*3)
  run('roundtrip',t,b'!'+b*3,want,b*3,start=1)
 for at in [-1,0,2**63-1]:run('read',t,b'\0'*(width-1),'0:0' if t.startswith('u64') else '0',b'',start=at,fields=1,kind='ERANGE')
 if t[0]=='f':
  for bits in ([0x80000000,0x7f800000,0x7fc00001,0x7f800001] if width==4 else [0x8000000000000000,0x7ff0000000000000,0x7ff8000000000001,0x7ff0000000000001]):
   data=bits.to_bytes(width,order);outbits=bits|0x400000 if width==4 and bits&0x7fffffff>0x7f800000 else bits
   run('roundtrip',t,data,'0',outbits.to_bytes(width,order),fields=1)
args.output.write_text(json.dumps(records,indent=2));print('passed',len(records),'calls')
