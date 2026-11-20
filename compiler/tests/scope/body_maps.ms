fn size(m: Map[String, Int]) Int:
	return 1

fn flags(m: Map[Int, Bool]) Bool:
	return true

fn nested(m: Map[String, List[Int]]) Int:
	return 2

fn build() Int:
	ages := {"ada": 36, "grace": 45}
	by_id: Map[Int, Bool] := {}
	names: Map[String, List[Int]] := {"a": [1, 2], "b": [3]}
	return size(ages) + nested(names)

fn use_flags() Bool:
	m := {1: true, 2: false}
	return flags(m)
