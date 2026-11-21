type P:
	name: String
	n: Int

type W:
	p: P
	tag: Int

fn set_count(n: Int, d: Int) Int:
	var p = P("a", n)
	p.n += d
	return p.n

fn set_name(n: Int) Int:
	var p = P("a", n)
	p.name = "bc"
	return p.name.length() + p.n

fn set_nested(n: Int, d: Int) Int:
	var w = W(P("a", n), 1)
	w.p.n = d
	w.tag += 1
	w.p.name = "xyz"
	return w.p.n + w.tag + w.p.name.length()

fn var W.retag(by: Int) Int:
	self.tag += by
	self.p.name = "z"
	return self.tag + self.p.n

fn retag_local(n: Int) Int:
	var w = W(P("a", n), 1)
	return w.retag(2) + w.tag
