import Bytes from "@std/bytes.ms"

fn a(b: Bytes) Int:
	return b.length()

fn c(b: Bytes) Bool:
	return b.is_empty()

fn d(b: Bytes) Bytes:
	return b.clone()

fn e(x: Int?) Bool:
	return x.is_none()

fn f(x: Int?) Int:
	return x.get_or(0)

fn g(s: String) Int:
	return s.index_of("a").get_or(-1)

fn i(x: String?) Bool:
	return x.is_some()

fn j(x: String?) String:
	return x.get_or("none")

fn k(s: String) String:
	return find(s, "a").get_or(s)

fn find(s: String, t: String) String?:
	if s.length() > t.length(): return s.upper()
	return none

fn l(s: String) Bool:
	return find(s, "a").is_none()

fn m(s: String, d: Int?) Int:
	return s.index_of("a").get_or(d)

fn main() Void:
	b := "ab".to_bytes()
	print(a(b))
	print(c(b))
	print(d(b).length())
	print(e(none))
	print(f(3))
	print(g("ba"))
	print(i("x"))
	print(j(none))
	print(k("ab"))
	print(l("b"))
	print(m("b", 4))
	print("abc".to_bytes().clone().is_empty())
	print(byte_at(b, 1))
	print(first_byte(b))
	print(byte_or(b, 9))
	print(item([1, 2], 1))
	print(item_or([1, 2], 5))
	print(name_or(["a"], -1))
	print(name_or(["a"], 3))

fn byte_at(b: Bytes, i: Int) Int:
	return b.get(i).to_int()

fn first_byte(b: Bytes) Int:
	return b.get_or(0).to_int()

fn byte_or(b: Bytes, i: Int) Int:
	return b.get_or(i, 7).to_int()

fn item(xs: List[Int], i: Int) Int:
	return xs.get(i)

fn item_or(xs: List[Int], i: Int) Int:
	return xs.get_or(i, 7)

fn name_or(xs: List[String], i: Int) String:
	return xs.get_or(i, "none")
