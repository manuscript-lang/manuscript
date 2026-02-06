// Test: {} is always a Map
// Maps should be real JS Maps, not plain objects
import { entries, keys, values } from "std/collections"

test "empty map creates Map"
  let m = {}
  assert typeof(m) == "map"

test "map with entries creates Map"
  let m = {a: 1, b: 2}
  assert typeof(m) == "map"

test "map get with bracket access"
  let m = {a: 1, b: 2}
  assert m["a"] == 1
  assert m["b"] == 2

test "map get returns null for missing key"
  let m = {a: 1}
  assert m["b"] == null

test "map set with bracket assignment"
  var m = {a: 1}
  m["b"] = 2
  assert m["b"] == 2

test "map iteration"
  let m = {a: 1, b: 2}
  var count = 0
  for entry in entries(m)
    count += 1
  assert count == 2

test "inline map access"
  let v = {x: 42}["x"]
  assert v == 42

test "map with string literal keys"
  let m = {"hello": 1, "world": 2}
  assert m["hello"] == 1

test "map spread"
  let m1 = {a: 1}
  let m2 = {b: 2, ...m1}
  assert m2["a"] == 1
  assert m2["b"] == 2

test "map len"
  let m = {a: 1, b: 2, c: 3}
  assert len(m) == 3

test "map keys"
  let m = {a: 1, b: 2}
  let k = keys(m)
  assert len(k) == 2

test "map values"
  let m = {a: 1, b: 2}
  let v = values(m)
  assert len(v) == 2
