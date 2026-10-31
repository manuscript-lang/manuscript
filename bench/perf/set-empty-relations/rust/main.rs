use std::{collections::HashSet,hint::black_box,time::Instant};
fn main(){
 let args:Vec<String>=std::env::args().skip(1).collect();
 let n:i64=args[1].parse().unwrap(); let repeats:i64=args[2].parse().unwrap(); let pattern=&args[3];
 let (mut left,mut right)=(HashSet::new(),HashSet::new());
 for i in 0..n {
  if pattern!="empty-left" {left.insert(i);}
  if pattern!="empty-right" { right.extend(match pattern.as_str(){ "disjoint"=>Some(i+n),"small-right"=>if i==0 {Some(n)}else{None},"early"=>Some(if i==0{n}else{i}),"late"=>Some(if i==n-1{n}else{i}),_=>Some(i)}); }
 }
 let start=Instant::now();let mut checksum=0i64;
 for _ in 0..repeats {
  let (a,b)=(black_box(&left),black_box(&right));
  let answer=match args[0].as_str(){"subset"=>a.is_subset(b),"superset"=>a.is_superset(b),"disjoint"=>a.is_disjoint(b),_=>panic!("unknown")};
  if answer{checksum+=1;}
 }
 println!("{} {}",start.elapsed().as_nanos(),checksum);
}
