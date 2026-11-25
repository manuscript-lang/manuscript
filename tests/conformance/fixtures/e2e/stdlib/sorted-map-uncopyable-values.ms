// conform: tags=maps,stdlib-collections,tier-core
// conform: phase=run
import (
	panic from "@std/core.ms",
	Regex, compile from "@std/regex.ms",
)

type Rule {
	re Regex
	name String
}

fn rule(pattern String) Rule {
	return Rule(compile(pattern).get(), pattern.clone())
}

import SortedMap, SortedSet from "@std/collections/sorted.ms"

fn main() Void {
	// A record holding a regular expression cannot be copied, so this map and its reads
	// must not need `Clonable`.
	var patterns = SortedMap[String, Rule]()
	patterns.add("b", rule("b+"))
	patterns.add("a", rule("a+"))
	patterns.add("c", rule("c+"))
	print(patterns.length())
	print(patterns.contains("b"))
	print((patterns.get("a") or panic("missing")).re.matches("aaa"))
	print(patterns.get("zz") == null)
	print(patterns.first() or "none")
	print(patterns.last() or "none")
	patterns.remove("b")
	print(patterns.length())

	entry := patterns.pop_first()
	print(entry != null)
	print(patterns.length())

	// Splitting a chunk moves keys and values without copying them.
	var many = SortedMap[Int, Rule]()
	for i in 0..300 {
		many.add(i, rule("x+"))
	}
	print(many.length())
	print((many.get(299) or panic("missing")).re.matches("xx"))

	// Entries and ordered views are read in place.
	near := many.ceiling(10) or panic("missing")
	print(near.key)
	print(near.value.re.matches("xx"))
	print((many.floor(1000) or panic("missing")).key)
	print(many.keys().length())
	print(many.values().length())

	var names = SortedSet[String]()
	names.add("m")
	names.add("a")
	print(names.first() or "none")
	tail()
}

fn tail() Void {
	var ids = SortedSet[Int]()
	for i in 0..10 {
		ids.add(i * 3)
	}
	print(ids.ceiling(4) or - 1)
	print(ids.floor(4) or - 1)
	print(ids.values().length())
}
