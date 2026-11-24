// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type P:
	n Int

fn reads(p P) Void:
	void p.n

fn apply(f fn(var P) Void) Int:
	var p = P(1)
	f(p)
	return p.n

fn bump(var p P) Void:
	p.n += 1

test "readers stand in for var functions":
	expect_equal(apply(p => void p.n), 1)?
	expect_equal(apply(reads), 1)?

	r := fn(p P) Void => void p.n
	expect_equal(apply(r), 1)?
	expect_equal(apply((var p) => p.n += 5), 6)?
	expect_equal(apply(bump), 2)?

type Holder:
	f fn(var Int) Void

fn run_int(f fn(var Int) Void) Int:
	var n = 3
	f(n)
	return n

fn run_str(f fn(var String) Void) String:
	var s = "ab"
	f(s)
	return s

fn make() fn(var Int) Void:
	return fn(n Int) Void => void n

test "scalars, strings, fields and returns":
	expect_equal(run_int(n => void n), 3)?
	expect_equal(run_str(s => void s.length()), "ab")?

	h := Holder(fn(n Int) Void => void n)
	expect_equal(run_int(h.f), 3)?
	expect_equal(run_int(make()), 3)?

	g fn(var Int) Void := fn(n Int) Void => void n
	expect_equal(run_int(g), 3)?

fn each_len[T](xs List[T], f fn(var T) Void) Int:
	return xs.length()

test "generic callee":
	expect_equal(each_len([1, 2], n => void n), 2)?
