package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestFaultSourceLocations(t *testing.T) {
	for _, tc := range []struct {
		name, source string
		tests        bool
		frames       []string
	}{

		{"Map add key fault", `fn crash() -> Int:
    return 1 / 0
export fn main() -> Int:
    let values = Map[Int, Int]()
    return values.add(crash(), 1).length()
`, false, []string{"fault.ms:2:14 in crash", "fault.ms:5:23 in main"}},
		{"bound Map add value fault", `fn crash() -> Int:
    return 1 / 0
export fn main() -> Int:
    let values = Map[Int, Int]()
    let add = values.add
    return add(value: crash(), key: 1).length()
`, false, []string{"fault.ms:2:14 in crash", "fault.ms:6:23 in main"}},
		{"List at unwrap out of range", `import List from "@std/collections.ms"
fn pick(values: List[Int], index: Int) -> Int:
    return values.at(index).unwrap()
export fn main() -> Int:
    return pick([1, 2, 3], 3)
`, false, []string{"fault.ms:3:29 in pick", "fault.ms:5:12 in main"}},
		{"Result unwrap", `fn deep(value: Result[Int, String]) -> Int:
    return value.unwrap()
export fn main() -> Int:
    return deep(error("expected failure"))
`, false, []string{"fault.ms:2:18 in deep", "fault.ms:4:12 in main"}},
		{"bound Result unwrap_error", `export fn main() -> Int:
    let value: Result[Int, String] = ok(0)
    let extract = value.unwrap_error
    return extract().scalar_length()
`, false, []string{"fault.ms:4:12 in main"}},
		{"Result callback fault", `fn crash(value: Int) -> Int:
    return 1 / value
export fn main() -> Int:
    let value: Result[Int, String] = ok(0)
    return value.map(crash).unwrap()
`, false, []string{"fault.ms:2:14 in crash", "fault.ms:5:18 in main"}},
		{"Result lazy fallback fault", `fn crash(cause: String) -> Int:
    return 1 / 0
export fn main() -> Int:
    let value: Result[Int, String] = error("expected failure")
    return value.unwrap_or_else(crash)
`, false, []string{"fault.ms:2:14 in crash", "fault.ms:5:18 in main"}},
		{"Map filter callback fault", `import Map from "@std/collections.ms"
fn crash(key: String, value: Int) -> Bool:
    return 1 / value == 0
export fn main() -> Int:
    let value: Map[String, Int] = {"a": 0}
    return value.filter(crash).length()
`, false, []string{"fault.ms:3:14 in crash", "fault.ms:6:18 in main"}},
		{"Set map callback fault", `import Set from "@std/collections.ms"
fn crash(value: Int) -> Int:
    return 1 / value
export fn main() -> Int:
    let value = Set[Int]().add(0)
    return value.map(crash).length()
`, false, []string{"fault.ms:3:14 in crash", "fault.ms:6:18 in main"}},
		{"Optional callback fault", `fn crash(value: Int) -> Optional[Int]:
    return some(1 / value)
export fn main() -> Int:
    let value: Optional[Int] = some(0)
    return value.and_then(crash).unwrap()
`, false, []string{"fault.ms:2:19 in crash", "fault.ms:5:18 in main"}},
		{"unwrap and caller", `import List from "@std/collections.ms"
fn deep(l: List[Int], i: Int) -> Int:
    return l.at(i).unwrap()
export fn main() -> Int:
    return deep(l: [1], i: 5)
`, false, []string{"fault.ms:3:20 in deep", "fault.ms:5:12 in main"}},
		{"test panic", `import panic from "@std/faults.ms"
test "several checks":
    let good = 2 + 3
    if good == 5:
        panic("last check failed")
`, true, []string{"fault.ms:5:9 in test several checks"}},
		{"multiline operand", `fn zero() -> Int:
    return 0
export fn main() -> Int:
    return (1 /
        zero())
`, false, []string{"fault.ms:4:15 in main"}},
		{"argument fault", `fn divide(value: Int) -> Int:
    return 1 / value
fn outer(value: Int) -> Int:
    return value
export fn main() -> Int:
    return outer(
        divide(0)
    )
`, false, []string{"fault.ms:2:14 in divide", "fault.ms:7:9 in main"}},
		{"default argument", `fn divide(value: Int = 1 / 0) -> Int:
    return value
export fn main() -> Int:
    return divide()
`, false, []string{"fault.ms:1:26 in divide", "fault.ms:4:12 in main"}},
		{"anonymous function", `export fn main() -> Int:
    let crash = fn() -> Int:
        return 1 / 0
    return crash()
`, false, []string{"fault.ms:3:18 in <anonymous>", "fault.ms:4:12 in main"}},
		{"generic function", `fn extract[T](value: Optional[T]) -> T:
    return value.unwrap()
export fn main() -> Int:
    return extract[Int](none)
`, false, []string{"fault.ms:2:18 in extract", "fault.ms:4:12 in main"}},
		{"bound method", `interface Crash:
    fn run() -> Int
type Item:
    value: Int
impl Crash for Item:
    fn run() -> Int:
        return 1 / self.value
export fn main() -> Int:
    let item = Item(0)
    let run = item.run
    return run()
`, false, []string{"fault.ms:7:18 in Item.run", "fault.ms:11:12 in main"}},
		{"destructuring", `import List from "@std/collections.ms"
fn empty() -> List[Int]:
    return []
export fn main() -> Int:
    let [value] = empty()
    return value
`, false, []string{"fault.ms:5:9 in main"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			result := compiler.CompileSource("fault.ms", tc.source, compiler.Options{Tests: tc.tests, Entry: !tc.tests})
			data, err := execute(t, result)
			if err == nil {
				t.Fatalf("expected fault: %s", data)
			}
			var frames []string
			for _, line := range strings.Split(string(data), "\n") {
				if frame, ok := strings.CutPrefix(line, "  at "); ok {
					frames = append(frames, frame)
				}
			}
			if strings.Join(frames, "\n") != strings.Join(tc.frames, "\n") {
				t.Fatalf("frames = %q, want %q; transcript:\n%s", frames, tc.frames, data)
			}
		})
	}
}
