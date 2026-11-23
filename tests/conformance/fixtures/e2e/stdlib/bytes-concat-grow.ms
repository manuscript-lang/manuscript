// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	Bytes from "@std/bytes.ms",
	expect_equal from "@std/test/test.ms",
)

test "concat onto a dying left side keeps both operands correct":
	var acc = Bytes([])
	piece := Bytes([1, 2])
	var i = 0
	while i < 1000:
		acc = acc.concat(piece)
		i += 1
	expect_equal(acc.length(), 2000)?
	expect_equal(acc.values().get(1999), 2)?

test "concat keeps a left side that is still used":
	left := Bytes([1])
	joined := left.concat(Bytes([2]))
	expect_equal(left.values(), [1])?
	expect_equal(joined.values(), [1, 2])?

test "concat onto a view and an empty buffer copies first":
	source := Bytes([7, 8, 9])
	var grown = source.view(0, 2)
	grown = grown.concat(Bytes([1]))
	expect_equal(source.values(), [7, 8, 9])?
	expect_equal(grown.values(), [7, 8, 1])?
	var empty = Bytes([])
	empty = empty.concat(Bytes([]))
	expect_equal(empty.length(), 0)?

test "concat of a part of itself":
	var v = Bytes([9, 8, 7])
	v = v.concat(v.view(0, 2).clone())
	expect_equal(v.values(), [9, 8, 7, 9, 8])?
