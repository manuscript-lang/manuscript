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
		{"rejected range grouping overflow", `fn probe() Int:
    let values = [1, 2, 3]
    var sum = 9223372036854775807
    for x in values:
        sum += x
    return sum
export fn main() Int:
    return probe()
`, false, []string{"fault.ms:5 in probe", "fault.ms:8 in main"}},
		{"rejected affine aggregate overflow", `fn probe() Int:
    var sum = 0
    var i = -9223372036854775808
    while i < -9223372036854775487:
        sum += i
        i += 1
    return sum
export fn main() Int:
    return probe()
`, false, []string{"fault.ms:5 in probe", "fault.ms:9 in main"}},
		{"try checked overflow", `import TextError from "@std/errors.ms"
fn checked(n: Int) Result[Int, TextError]:
    if n < 0:
        return error(TextError("negative"))
    return ok(n + 1)
fn chain(n: Int) Result[Int, TextError]:
    let value = try checked(n)
    return ok(value)
export fn main() Int:
    return chain(9223372036854775807).get()
`, false, []string{"fault.ms:5 in checked", "fault.ms:7 in chain", "fault.ms:10 in main"}},

		{"checked record method", `interface Counter:
    fn bump(by: Int) Int
type Cell:
    total: Int
impl Counter for Cell:
    fn bump(by: Int) Int:
        self.total += by
        return self.total
fn probe(value: Int) Int:
    let cell = Cell(0)
    cell.bump(value)
    cell.bump(1)
    return cell.total
export fn main() Int:
    return probe(9223372036854775807)
`, false, []string{"fault.ms:7 in Cell.bump", "fault.ms:12 in probe", "fault.ms:15 in main"}},
		{"presence tail argument fault", `import {read_line, ReadStream, stdin} from "@std/io.ms"
fn limit() Int:
    return 1 / 0
fn probe(input: ReadStream) Bool:
    if let line = read_line(input, limit()):
        return line.is_some()
    return false
export fn main() Int:
    if probe(stdin()): return 1
    return 0
`, false, []string{"fault.ms:3 in limit", "fault.ms:5 in probe", "fault.ms:9 in main"}},
		{"Map add key fault", `fn crash() Int:
    return 1 / 0
export fn main() Int:
    let values = Map[Int, Int]()
    return values.add(crash(), 1).length()
`, false, []string{"fault.ms:2 in crash", "fault.ms:5 in main"}},
		{"bound Map add value fault", `fn crash() Int:
    return 1 / 0
export fn main() Int:
    let values = Map[Int, Int]()
    let add = values.add
    return add(value: crash(), key: 1).length()
`, false, []string{"fault.ms:2 in crash", "fault.ms:6 in main"}},
		{"List at unwrap out of range", `fn pick(values: List[Int], index: Int) Int:
    return values.get(index)
export fn main() Int:
    return pick([1, 2, 3], 3)
`, false, []string{"fault.ms:2 in pick", "fault.ms:4 in main"}},
		{"Result unwrap", `import {TextError} from "@std/errors.ms"
fn deep(value: Result[Int, TextError]) Int:
    return value.get()
export fn main() Int:
    return deep(error(TextError("expected failure")))
`, false, []string{"fault.ms:3 in deep", "fault.ms:5 in main"}},
		{"bound Result err", `import {TextError} from "@std/errors.ms"
export fn main() Int:
    let value: Result[Int, TextError] = ok(0)
    let extract = value.err
    return extract().text.scalar_length()
`, false, []string{"fault.ms:5 in main"}},
		{"Result callback fault", `import {TextError} from "@std/errors.ms"
fn crash(value: Int) Int:
    return 1 / value
export fn main() Int:
    let value: Result[Int, TextError] = ok(0)
    return value.map(crash).get()
`, false, []string{"fault.ms:3 in crash", "fault.ms:6 in main"}},
		{"Result lazy fallback fault", `import {TextError} from "@std/errors.ms"
fn crash(cause: TextError) Int:
    return 1 / 0
export fn main() Int:
    let value: Result[Int, TextError] = error(TextError("expected failure"))
    return value.or_else(crash)
`, false, []string{"fault.ms:3 in crash", "fault.ms:6 in main"}},
		{"Map filter callback fault", `fn crash(key: String, value: Int) Bool:
    return 1 / value == 0
export fn main() Int:
    let value: Map[String, Int] = {"a": 0}
    return value.filter(crash).length()
`, false, []string{"fault.ms:2 in crash", "fault.ms:5 in main"}},
		{"Set map callback fault", `fn crash(value: Int) Int:
    return 1 / value
export fn main() Int:
    let value = Set[Int]().add(0)
    return value.map(crash).length()
`, false, []string{"fault.ms:2 in crash", "fault.ms:5 in main"}},
		{"Optional callback fault", `fn crash(value: Int) Optional[Int]:
    return some(1 / value)
export fn main() Int:
    let value: Optional[Int] = some(0)
    return value.and_then(crash).get()
`, false, []string{"fault.ms:2 in crash", "fault.ms:5 in main"}},
		{"unwrap and caller", `fn deep(l: List[Int], i: Int) Int:
    return l.get(i)
export fn main() Int:
    return deep(l: [1], i: 5)
`, false, []string{"fault.ms:2 in deep", "fault.ms:4 in main"}},
		{"test panic", `import panic from "@std/faults.ms"
test "several checks":
    let good = 2 + 3
    if good == 5:
        panic("last check failed")
`, true, []string{"fault.ms:5 in test several checks"}},
		{"multiline operand", `fn zero() Int:
    return 0
export fn main() Int:
    return (1 /
        zero())
`, false, []string{"fault.ms:4 in main"}},
		{"argument fault", `fn divide(value: Int) Int:
    return 1 / value
fn outer(value: Int) Int:
    return value
export fn main() Int:
    return outer(
        divide(0)
    )
`, false, []string{"fault.ms:2 in divide", "fault.ms:6 in main"}},
		{"default argument", `fn divide(value: Int = 1 / 0) Int:
    return value
export fn main() Int:
    return divide()
`, false, []string{"fault.ms:1 in divide", "fault.ms:4 in main"}},
		{"anonymous function", `export fn main() Int:
    let crash = fn() Int:
        return 1 / 0
    return crash()
`, false, []string{"fault.ms:3 in <anonymous>", "fault.ms:4 in main"}},
		{"generic function", `fn extract[T](value: Optional[T]) T:
    return value.get()
export fn main() Int:
    return extract[Int](none)
`, false, []string{"fault.ms:2 in extract", "fault.ms:4 in main"}},
		{"bound method", `interface Crash:
    fn run() Int
type Item:
    value: Int
impl Crash for Item:
    fn run() Int:
        return 1 / self.value
export fn main() Int:
    let item = Item(0)
    let run = item.run
    return run()
`, false, []string{"fault.ms:7 in Item.run", "fault.ms:11 in main"}},
		{"destructuring", `fn empty() List[Int]:
    return []
export fn main() Int:
    let [value] = empty()
    return value
`, false, []string{"fault.ms:4 in main"}},
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
