use ms_syntax::{lexer::lex, parser::parse, parse_partial};
use std::{hint::black_box, sync::Arc, time::{Duration, Instant}};
fn main() {
 std::thread::Builder::new().stack_size(64 << 20).spawn(run).unwrap().join().unwrap();
}
fn run() {
 let args:Vec<_>=std::env::args().collect();
 let mode=&args[1];
 let file:Arc<str>=Arc::from(args[2].as_str());
 let text=std::fs::read_to_string(&args[2]).unwrap();
 let pass=|| -> (u64,u64) {
  if mode=="lex" {let out=black_box(lex(black_box(&file),black_box(&text)).unwrap());return(out.tokens.len() as u64,0);}
  if mode=="parse" {let out=black_box(parse(black_box(&file),black_box(&text)).unwrap());return(u64::from(out.node_count),0);}
  assert_eq!(mode,"partial");
  let (out,issues)=black_box(parse_partial(black_box(&file),black_box(&text)));
  (u64::from(out.node_count),issues.len() as u64)
 };
 let expected=pass(); for _ in 0..3 {assert_eq!(pass(),expected);}
 let start=Instant::now(); let mut passes=0u64; let mut checksum=0u64;
 loop {for _ in 0..16 {let value=pass();assert_eq!(value,expected);checksum=checksum.wrapping_add(value.0+value.1);passes+=1;}if start.elapsed()>=Duration::from_millis(30){break;}}
 let ns=start.elapsed().as_nanos();
 assert_eq!(checksum,(expected.0+expected.1)*passes);
 println!("{{\"elapsed_ns\":{ns},\"passes\":{passes},\"units\":{},\"diagnostics\":{},\"checksum\":{checksum}}}",expected.0,expected.1);
}
