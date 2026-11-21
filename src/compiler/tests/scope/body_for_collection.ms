fn total(m: Map[String, Int]) Int:
	var n = 0
	for entry in m:
		n += entry.value
	return n

fn count(s: Set[Int]) Int:
	var n = 0
	for x in s:
		n += x
	return n
