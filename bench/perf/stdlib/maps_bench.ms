import words from "./src/harness.ms"

type Cell:
	x Int
	y Int

bench "map.int_put_get" per 200000:
	var m = Map[Int, Int]()
	for i in 0..100000:
		m.add(i, i * 2)

	var n = 0
	for i in 0..100000:
		n += m.get_or(i, 0)
	n

bench "map.record_key_get" per 200000:
	var m = Map[Cell, Int]()
	for i in 0..100000:
		m.add(Cell(x: i, y: i * 2), i)

	var n = 0
	for i in 0..100000:
		n += m.get_or(Cell(x: i, y: i * 2), 0)
	n

bench "map.string_put_get" per 100000:
	keys := words(50000)
	var m = Map[String, Int]()
	for k in keys:
		m.add(k.clone(), 1)

	var n = 0
	for k in keys:
		n += m.get_or(k, 0)
	n

bench "map.get_let" per 100000:
	keys := words(50000)
	var m = Map[String, String]()
	for k in keys:
		m.add(k.clone(), k.clone())

	var n = 0

	for k in keys:
		found := m.get(k)
		if found != null:
			n += found.length()

	n

bench "map.get_if_let" per 100000:
	keys := words(50000)
	var m = Map[String, String]()
	for k in keys:
		m.add(k.clone(), k.clone())

	var n = 0

	for k in keys:
		v := m.get(k)
		if v != null:
			n += v.length()

	n

bench "map.get_chain" per 100000:
	keys := words(50000)
	var m = Map[String, String]()
	for k in keys:
		m.add(k.clone(), k.clone())

	var n = 0
	for k in keys:
		n += m.get_or(k, "").length()
	n

bench "map.get_or" per 100000:
	keys := words(50000)
	var m = Map[String, String]()
	for k in keys:
		m.add(k.clone(), k.clone())

	var n = 0
	for k in keys:
		n += m.get_or(key: k, fallback: "").length()
	n

bench "map.iterate_entries" per 100000:
	var m = Map[Int, Int]()
	for i in 0..100000:
		m.add(i, i)

	var n = 0
	for e in m.entries():
		n += e.value
	n

bench "set.add_contains" per 200000:
	var s = Set[Int]()
	for i in 0..100000:
		s.add(i)

	var n = 0
	for i in 0..100000:
		if s.contains(i): n += 1
	n
