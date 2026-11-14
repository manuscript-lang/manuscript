use std::net::ToSocketAddrs; use std::time::Instant;
fn main(){ let t0=Instant::now(); let mut n=0; for _ in 0..20000 { n+=("localhost",0u16).to_socket_addrs().unwrap().count(); } println!("lookup {} ns/call {n}", t0.elapsed().as_nanos()/20000); }
