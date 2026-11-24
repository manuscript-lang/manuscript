// conform: tags=closures,faults,generics,lists,modules,mutation,optional,stdlib-bytes,stdlib-testing,testing,tier-stdlib,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/stdlib/bytes-split.ms
import (
	Bytes from "@std/bytes.ms",
	expect_equal, expect_false from "@std/test/test.ms",
)

test "Bytes split is binary safe":
	data := Bytes([255, 0, 1, 0, 254])
	expect_equal(data.split(Bytes([0])), [Bytes([255]), Bytes([1]), Bytes([254])])?

test "Bytes split handles exact and nonoverlapping separators":
	empty := Bytes([])
	expect_equal(
		Bytes([0, 7, 0]).split(Bytes([0])),
		[empty.clone(), Bytes([7]), empty.clone()],
	)?
	expect_equal(
		Bytes([0, 0]).split(Bytes([0])),
		[empty.clone(), empty.clone(), empty.clone()],
	)?
	expect_equal(
		Bytes([255, 0, 9, 255, 0]).split(Bytes([255, 0])),
		[empty.clone(), Bytes([9]), empty.clone()],
	)?
	expect_equal(Bytes([1, 1, 1]).split(Bytes([1, 1])), [empty.clone(), Bytes([1])])?
	expect_equal(Bytes([1]).split(Bytes([1, 2])), [Bytes([1])])?
	expect_equal(empty.split(Bytes([0])), [empty])?

test "Bytes empty separator splits bytes without decoding":
	empty := Bytes([])
	expect_false(not (empty.split(empty).is_empty()))?
	expect_equal(
		Bytes([0, 255, 128]).split(empty),
		[Bytes([0]), Bytes([255]), Bytes([128])],
	)?

	scalars := "é".to_bytes().split(empty)
	expect_equal(scalars, [Bytes([195]), Bytes([169])])?
	expect_false(scalars.get(0).decode_utf8() != null)?
	expect_equal("é".to_bytes().split(Bytes([169])), [Bytes([195]), empty])?

test "Bytes split keeps empty parts and splits empty separators per byte":
	data := Bytes([1, 0, 2, 0, 3, 0])
	separator := Bytes([0])
	expected := [Bytes([1]), Bytes([2]), Bytes([3]), Bytes([])]
	expect_equal(data.split(separator), expected)?
	expect_equal(Bytes([]).split(separator), [Bytes([])])?
	expect_equal(
		data.split(Bytes([])),
		[Bytes([1]), Bytes([0]), Bytes([2]), Bytes([0]), Bytes([3]), Bytes([0])],
	)?

fn split_then[T](data Bytes, separator Bytes, transform fn(List[Bytes]) T) T:
	return data.split(separator) | transform

fn call_split(operation fn(Bytes) List[Bytes]) List[Bytes]:
	return operation(Bytes([0]))

test "Bytes split bound methods and generic forwarding retain contracts":
	var data = Bytes([1, 0, 2])
	split := data.clone().split
	typed fn(Bytes) List[Bytes] := data.clone().split
	data = Bytes([9])
	expect_equal(split(Bytes([0])), [Bytes([1]), Bytes([2])])?
	expect_equal(call_split(typed), [Bytes([1]), Bytes([2])])?
	expect_false(
		(
			split_then[Bool](
				Bytes([1, 0, 2]),
				Bytes([0]),
				value => value.length() == 2
			) != true
		)
	)?

test "Bytes split returns independent List storage and immutable views":
	data := Bytes([1, 0, 2])
	var first = data.split(Bytes([0]))
	second := data.split(Bytes([0]))
	payload := first.get(0).clone()
	edited := payload.with_value(0, 99)
	var extracted = payload.values()
	extracted.set(0, 88)
	first.set(0, Bytes([77]))
	first.append(Bytes([66]))
	expect_false(
		(
			edited != Bytes([99])
			or payload != Bytes([1])
			or data != Bytes([1, 0, 2])
		)
	)?
	expect_equal(second, [Bytes([1]), Bytes([2])])?

	empty := Bytes([])
	var parts = data.split(Bytes([0]))
	parts.append(empty.clone())
	expect_equal(data.split(Bytes([0])).length(), 2)?

	var no_parts = empty.split(empty)
	no_parts.append(Bytes([1]))
	expect_false(not (empty.split(empty).is_empty()))?
