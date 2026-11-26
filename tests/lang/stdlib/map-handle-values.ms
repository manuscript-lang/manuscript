// conform: tags=maps,scope-cleanup,tier-core
// conform: phase=run
import panic from "@std/core.ms"
import Regex, compile from "@std/regex.ms"

fn main() Void {
	// A native handle is a value of a map: it is stored, replaced, removed and released with it.
	var patterns = Map[String, Regex]()
	patterns.add("a", compile("a+").get())
	patterns.add("b", compile("b+").get())
	print(patterns.length())
	print((patterns.get("a") or panic("missing")).matches("aaa"))
	print(patterns["b"].matches("bb"))

	patterns.add("a", compile("x+").get())
	print((patterns.get("a") or panic("missing")).matches("aaa"))

	patterns.remove("b")
	print(patterns.contains("b"))

	patterns.clear()
	print(patterns.length())
}
// expect-exit: 0
// expect-stdout: 2
// expect-stdout: true
// expect-stdout: true
// expect-stdout: false
// expect-stdout: false
// expect-stdout: 0
