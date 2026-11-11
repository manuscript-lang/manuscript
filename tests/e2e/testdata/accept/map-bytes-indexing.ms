import expect_equal from "@std/test/test.ms"

fn total(scores: Map[String, Int]) Int:
	return scores["a"] + scores["b"]

fn sizes(var table: Map[Int, String]) Int:
	table[1] = "one"
	return table[1].length()

test "map index reads and writes":
	var m = {"a": 1, "b": 2}
	m["a"] | expect_equal(1)?
	m["c"] = 3
	m["c"] | expect_equal(3)?
	m["a"] += 10
	m["a"] | expect_equal(11)?
	total(m) | expect_equal(13)?
	m.length() | expect_equal(3)?

test "map index assignment keeps insertion position":
	var m = {"x": 1, "y": 2, "z": 3}
	m["y"] = 20
	m.keys() | expect_equal(["x", "y", "z"])?
	m["y"] | expect_equal(20)?

test "map index with Int keys and String values":
	var table: Map[Int, String] = {}
	sizes(var table) | expect_equal(3)?

	var counts = {1: 10, 2: 20}
	counts[2] *= 2
	counts[2] | expect_equal(40)?

test "bytes index":
	data := "abc".to_bytes()
	data[0] | expect_equal(97)?
	data[2] | expect_equal(99)?
	data[-1] | expect_equal(99)?
	data[-3] | expect_equal(97)?
