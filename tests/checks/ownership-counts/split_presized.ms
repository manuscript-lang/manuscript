// expect-debug: allocs=1003 alloc_bytes=512203
// expect-release: allocs=1003 alloc_bytes=512203
// `split` counts the pieces first and sizes the list once: one allocation per call, where a
// list that grows by doubling made four for these twenty-one pieces.
fn pieces() String {
	return f"alpha,beta,gamma,delta,epsilon,zeta,eta,theta,iota,kappa,lambda,mu,nu,xi,omicron,pi,rho,sigma,tau,upsilon,{1}"
}

export fn main() Int {
	text := pieces()
	var n = 0
	for i in 0..1000 {
		n += text.split(",").collect().length() + i - i
	}
	return n % 100
}
