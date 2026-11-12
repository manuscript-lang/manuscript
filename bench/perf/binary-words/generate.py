from pathlib import Path
P=Path(__file__).parent
kinds=[('i8','int8','append_int8','Int8',1),('u8','uint8','append','UInt8',1)]
for n in [16,32,64]:
 for sign in ['i','u']:
  for endian in ['le','be']:
   t=('Int' if sign=='i' else 'UInt')+str(n)
   if n==64 and sign=='i':t='Int'
   meth=('int' if sign=='i' else 'uint')+str(n)+'_'+endian
   kinds.append((f'{sign}{n}{endian}',meth,'append_'+meth,t,n//8))
for n in [32,64]:
 for endian in ['le','be']:kinds.append((f'f{n}{endian}',f'float{n}_{endian}',f'append_float{n}_{endian}','Float32' if n==32 else 'Float',n//8))
s='''import (
 Bytes, BytesBuilder from "@std/bytes.ms",
 panic from "@std/core.ms",
 arguments from "@std/os/env.ms",
 read_file from "@std/os/fs.ms",
 monotonic from "@std/time.ms",
)
'''
for name,read,append,t,width in kinds:
 parse='args[7].parse_int().get()'
 if t=='UInt64':parse='parts[0].parse_int().get().to_uint64().get(0) * 4294967296 + parts[1].parse_int().get().to_uint64().get(0)'
 elif t=='Float':parse='args[7].parse_float().get()'
 elif t=='Float32':parse='args[7].parse_float().get().to_float32().get()'
 elif t!='Int':parse+='.'+('to_'+t.lower())+'().get()'
 s+=f'''
fn work_{name}(op: String, data: Bytes, expected: Bytes, start: Int, fields: Int, count: Int, want: {t}, kind: String) Int:
 var checksum = 0
 if op == "read":
  for unused in 0..count:
   for i in 0..fields:
    got := data.{read}(start + i * {width})
    if kind == "OK":
     if got.get() != want: panic("wrong value")
    else:
     if got.is_ok(): panic("expected error")
     if got.err().kind != kind or got.err().message != "{'binary: out of range' if t=='UInt64' else 'binary: value out of range'}": panic("wrong error")
    checksum += 1
  return checksum
 if op == "pack":
  for unused in 0..count:
   var out = BytesBuilder()
   for i in 0..fields:
    out.{append}(want)
   actual := out.build()
   if actual != expected: panic("wrong output")
   checksum += actual.length() + 1
  return checksum
 for unused in 0..count:
  var out = BytesBuilder()
  for i in 0..fields:
   out.{append}(data.{read}(start + i * {width}).get())
  actual := out.build()
  if actual != expected: panic("wrong output")
  checksum += actual.length() + 1
 return checksum

fn launch_{name}(args: List[String]) Int:
 op := args[0]
 data := read_file(args[2]).wait().get()
 expected := read_file(args[3]).wait().get()
 start := args[4].parse_int().get()
 fields := args[5].parse_int().get()
 count := args[6].parse_int().get()
'''
 if t=='UInt64':s+=' parts := args[7].split(":")\n'
 s+=f''' want := {parse}
 kind := args[8]
 warm := if count / 10 > 0: count / 10 else: 1
 warm_sum := work_{name}(op, data, expected, start, fields, warm, want, kind)
 begin := monotonic()
 checksum := work_{name}(op, data, expected, start, fields, count, want, kind)
 elapsed := monotonic().difference(begin).to_nanoseconds()
 print("{{count}},{{elapsed}},{{checksum}},{{warm_sum}}")
 return 0
'''
s+='\nexport fn main() Int:\n args := arguments()\n match args[1]:\n'
for name,*_ in kinds:s+=f'  "{name}": return launch_{name}(args)\n'
s+='  _: return 2\n'
s='\n'.join('\t'*(len(line)-len(line.lstrip(' ')))+line.lstrip(' ') for line in s.splitlines())+'\n'
(P/'probe.ms').write_text(s)
