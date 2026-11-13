import (
	Bytes from "@std/bytes.ms",
	monotonic from "@std/time.ms",
)

fn us(a: Int, b: Int) Int:
	return (b - a) / 1000

fn sum_get(xs: List[Int], n: Int) Int:
	var s = 0
	for r in 0..n:
		for i in 0..xs.length():
			s += xs.get(i, 0)
	return s

fn sum_firstlast(xs: List[Int], n: Int) Int:
	var s = 0
	for r in 0..n:
		s += xs.first().get(0) + xs.last().get(0) + r
	return s

fn bytes_get(b: Bytes, n: Int) Int:
	var s = 0
	for r in 0..n:
		for i in 0..b.length():
			s += b.get(i, 0).to_int()
	return s

fn near(b: Bytes, n: Int) Int:
	var s = 0
	for r in 0..n:
		for i in 0..(b.length() - 20):
			s += b.index_of_byte(104, i).get(0)
	return s

fn main() Unit:
	var xs = List[Int]()
	for i in 0..1000:
		xs.append(i)

	b := "abcdefghij".repeat(100).get().to_bytes()
	t0 := monotonic().tick
	s1 := sum_get(xs, 20000)
	t1 := monotonic().tick
	s2 := sum_firstlast(xs, 5000000)
	t2 := monotonic().tick
	s3 := bytes_get(b, 20000)
	t3 := monotonic().tick
	s4 := near(b, 2000)
	t4 := monotonic().tick
	print("list-get {us(t0, t1)} {s1}")
	print("first-last {us(t1, t2)} {s2}")
	print("bytes-get {us(t2, t3)} {s3}")
	print("index-of-byte {us(t3, t4)} {s4}")
