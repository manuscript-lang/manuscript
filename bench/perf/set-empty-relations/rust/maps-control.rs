use std::{collections::HashMap,hint::black_box,time::Instant};
fn main(){
 let args:Vec<String>=std::env::args().skip(1).collect();
 let n:i64=args[1].parse().unwrap();let repeats:i64=args[2].parse().unwrap();let prefix=&args[3];
 let keys:Vec<String>=(0..2*n).map(|i|format!("{prefix}{i}")).collect();
 let mut ints=HashMap::new();let mut strings=HashMap::new();
 for i in 0..n {ints.insert(i,i*2);strings.insert(keys[i as usize].clone(),i*2);}
 let start=Instant::now();let mut checksum=0i64;
 for _ in 0..repeats {
  match args[0].as_str(){
   "int_get"=>{let map=black_box(&ints);for i in 0..2*n{checksum+=map.get(&i).copied().unwrap_or(0);}},
   "string_get"=>{let map=black_box(&strings);for key in &keys{checksum+=map.get(key).copied().unwrap_or(0);}},
   "int_update"=>{let map=black_box(&mut ints);for i in 0..n{map.insert(i,i*2);}for i in 0..2*n{checksum+=map.get(&i).copied().unwrap_or(0);}},
   "string_update"=>{let map=black_box(&mut strings);for i in 0..n{map.insert(keys[i as usize].clone(),i*2);}for key in &keys{checksum+=map.get(key).copied().unwrap_or(0);}},
   _=>panic!("unknown")
  }
 }
 println!("{} {}",start.elapsed().as_nanos(),checksum);
}
