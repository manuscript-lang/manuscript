use std::time::Instant;
fn lcg(x:i64)->i64{(x*1103515245+12345)%2147483648}
fn rep(name:&str,t:Instant,s:i64){println!("{} {} ms {}",name,t.elapsed().as_millis(),s);}
fn main(){
 let n=1000000i64; let mut x=7i64;
 let mut words:Vec<String>=vec![]; for _ in 0..n{x=lcg(x);words.push(format!("w{}-{}",x%100000,x/7%977));}
 let text=words.join(" ");
 let mut t=Instant::now(); let mut s=0i64;
 for _ in 0..200{ s+=text.find("w99999-976 w0").map(|v|v as i64).unwrap_or(-1);} rep("index_of_big",t,s);
 t=Instant::now(); s=0; for _ in 0..200{ if text.contains("zzzz"){s+=1;}} rep("contains_miss_big",t,s);
 t=Instant::now(); s=text.split_whitespace().collect::<Vec<_>>().len() as i64; rep("fields",t,s);
 t=Instant::now(); s=0; for w in &words{ s+=w.trim_matches('w').len() as i64;} rep("trim_chars",t,s);
 t=Instant::now(); let mut v=words.clone(); v.sort_by(|a,b|a.cmp(b)); rep("sort_strings",t,v[0].len() as i64);
 t=Instant::now(); s=0; for w in &words{ s+=format!("{:0>14}",w).len() as i64;} rep("pad",t,s);
}
