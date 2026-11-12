// conform: tags=testing,records,mutation,tier-stdlib
// conform: phase=test
import (
	Bytes from "@std/bytes.ms",
	expect_equal from "@std/test/test.ms",
)

type Cursor:
	data: Bytes
	start: Int
	stop: Int
	label: String
	seen: List[Int]
	done: Bool

fn Cursor.peek() Int:
	return self.data.get(self.start, 0).to_int()

fn var Cursor.advance() Int:
	at := self.start
	if self.start >= self.stop:
		self.done = true
		return -1
	self.start += 1
	self.seen.append(at)
	return self.data[at].to_int()

fn var Cursor.reset(label: String) Unit:
	self.start = 0
	self.label = label
	self.seen = []

fn fill(var c: Cursor, n: Int) Int:
	var sum = 0
	for step in 0..n:
		if step < 0: return 0
		v := c.advance()
		if v < 0: return sum
		sum += v
	return sum

fn replace_whole(var c: Cursor) Unit:
	c = Cursor("abc".to_bytes(), 1, 3, "swapped", [], false)

test "bytes reads index, wrap negative and use defaults":
	b := "hello".to_bytes()
	expect_equal(b[0].to_int(), 104)?
	expect_equal(b[-1].to_int(), 111)?
	expect_equal(b.get(1, 7).to_int(), 101)?
	expect_equal(b.get(9, 7).to_int(), 7)?
	expect_equal(b.get(-9, 3).to_int(), 3)?
	expect_equal(b.get(-5, 3).to_int(), 104)?
	expect_equal(b.get(2, none), 108)?

test "var record methods change fields in place":
	var c = Cursor("abcd".to_bytes(), 0, 3, "first", [], false)
	expect_equal(c.peek(), 97)?
	expect_equal(fill(var c, 2), 97 + 98)?
	expect_equal(c.start, 2)?
	expect_equal(c.seen, [0, 1])?
	expect_equal(fill(var c, 5), 99)?
	expect_equal(c.done, true)?
	expect_equal(c.peek(), 100)?
	c.reset("again")
	expect_equal(c.label, "again")?
	expect_equal(c.start, 0)?
	expect_equal(c.seen.length(), 0)?
	expect_equal(c.advance(), 97)?

test "a var record parameter can be replaced whole":
	var c = Cursor("xyz".to_bytes(), 0, 3, "orig", [5], false)
	replace_whole(var c)
	expect_equal(c.label, "swapped")?
	expect_equal(c.peek(), 98)?
	expect_equal(c.seen.length(), 0)?
