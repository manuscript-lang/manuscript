use ms_lsp::{analysis::{Document, Documents}, completion, json::{Json, Escape}, text, uri};
use std::{hint::black_box, time::Instant};
fn fp(s:&str)->u64{s.bytes().fold(0xcbf29ce484222325,|a,b|(a^u64::from(b)).wrapping_mul(0x100000001b3))}
fn main(){
 let a:Vec<_>=std::env::args().collect(); let mode=&a[1]; let n:usize=a[2].parse().unwrap(); let rounds:u32=a[3].parse().unwrap();
 let source=match mode.as_str(){
  "completion" | "completion-doc"=>{
   let doc=if mode=="completion-doc" {"# ".to_owned()+&"sample ".repeat(50)+"\n"}else{String::new()};
   let mut s=(0..n).map(|i|doc.clone()+&include_str!("../function.ms").replace("item_N",&format!("item_{i}"))).collect::<String>();
   s.push_str(include_str!("../cursor.ms"));s
  },
  "nesting"=>include_str!("../expression.ms").replace("{{expr}}",&("f(".repeat(n)+"1"+&")".repeat(n))),
  "calls"=>include_str!("../expression.ms").replace("{{expr}}",&("x".repeat(100)+&".m(1, 2, 3)".repeat(n))),
  _=>panic!("mode")
 };
 let doc=Document::new(uri::file_uri("/tmp/ms-tooling-discovery.ms"),source.clone());
 let at=source.rfind("    \n").map(|i|i+4).unwrap_or(source.len());let p=text::position(&source,at);
 let query=||->(u64,usize){
  if mode.starts_with("completion"){
   let items=completion::completion_at(&doc,&Documents::new(),p,false).unwrap();assert_eq!(items.iter().filter(|x|x.json().get("label").and_then(|v|v.as_str()).is_some_and(|s|s.starts_with("item_"))).count(),n);let size=items.len();
   (fp(&Json::Arr(items.iter().map(|x|x.json()).collect()).compact(Escape::Plain)),size)
  }else{
   let out=ms_syntax::format(&"/tmp/ms-tooling-discovery.ms".into(),&source).unwrap();
   (fp(&out),out.len())
  }
 };
 if !mode.starts_with("completion"){let out=ms_syntax::format(&"/tmp/ms-tooling-discovery.ms".into(),&source).unwrap();assert_eq!(ms_syntax::format(&"/tmp/ms-tooling-discovery.ms".into(),&out).unwrap(),out);}
 let expected=black_box(query());let now=Instant::now();let mut sum=0u64;
 for _ in 0..rounds{let x=black_box(query());assert_eq!(x,expected);sum=sum.wrapping_add(x.0)}
 let elapsed=now.elapsed().as_nanos();assert_eq!(sum,expected.0.wrapping_mul(rounds as u64));
 println!("{mode},{n},{rounds},{elapsed},{},{},{}",expected.0,source.len(),expected.1)
}
