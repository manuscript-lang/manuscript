// ms: allow_effect std.fs.read
//   ms:  allow_effect   db.*  

 // ms: effect a.b 
// ms: effect  
// ms:effect x
// ms: allow_effect
fn f() {}

// ms: allow_effect *

// ms: effect z
fn g() {}
// plain
let x = 1