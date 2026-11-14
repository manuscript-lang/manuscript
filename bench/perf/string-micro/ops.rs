use std::time::Instant;
use std::hash::{Hash,Hasher};
fn lcg(x:i64)->i64{(x*1103515245+12345)%2147483648}
fn rep(name:&str,t:Instant,s:i64){println!("{} {} ms {}",name,t.elapsed().as_millis(),s);}
fn main(){
 let n=1000000i64; let mut x=7i64;
 let mut words:Vec<String>=vec![]; for _ in 0..n{x=lcg(x);words.push(format!("w{}-{}",x%100000,x/7%977));}
 let mut nums:Vec<String>=vec![]; for _ in 0..n{x=lcg(x);nums.push((x%1000000007).to_string());}
 let mut t=Instant::now(); let mut s=0i64;
 for w in &nums{s+=w.parse::<i64>().unwrap_or(0);} rep("parse_int",t,s);
 t=Instant::now(); s=0; for i in 0..n{s+=(i*31).to_string().len() as i64;} rep("int_to_string",t,s);
 t=Instant::now(); s=0; for i in 0..n{s+=format!("a{}:{}b",i,i*3).len() as i64;} rep("interp",t,s);
 t=Instant::now(); s=0; for w in &words{if w.starts_with("w9"){s+=1;}} rep("starts_with",t,s);
 t=Instant::now(); s=0; for w in &words{for c in w.chars(){s+=c.len_utf8() as i64;}} rep("scalars_iter",t,s);
 t=Instant::now(); s=0; for w in &words{s+=w.split('-').collect::<Vec<_>>().len() as i64;} rep("split_small",t,s);
 let line=words.join(",");
 t=Instant::now(); s=line.split(',').collect::<Vec<_>>().len() as i64; rep("split_big",t,s);
 t=Instant::now(); s=words.join(" ").len() as i64; rep("join",t,s);
 t=Instant::now(); s=line.replace(",",";;").len() as i64; rep("replace_big",t,s);
 t=Instant::now(); s=0; for w in &words{s+=w.to_uppercase().len() as i64;} rep("upper",t,s);
 t=Instant::now(); s=0; for w in &words{s+=w.chars().rev().collect::<String>().len() as i64;} rep("reverse",t,s);
 t=Instant::now(); s=0; for w in &words{s+=w.repeat(3).len() as i64;} rep("repeat",t,s);
 t=Instant::now(); s=0; for w in &words{if w=="w5-5"{s+=1;}} rep("equal",t,s);
 t=Instant::now(); s=line.lines().count() as i64; rep("lines",t,s);
 t=Instant::now(); s=0; for w in &words{let mut h=std::collections::hash_map::DefaultHasher::new(); w.hash(&mut h); s+=(h.finish()%7) as i64;} rep("hash",t,s);
 t=Instant::now(); s=0; for i in 0..n{s+=format!("{}",i as f64*1.37).len() as i64;} rep("float_to_string",t,s);
 t=Instant::now(); s=0; for i in 0..n{s+=format!("{}",i as f64*1.37).parse::<f64>().unwrap_or(0.0) as i64;} rep("float_parse",t,s);
}
