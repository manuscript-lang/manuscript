package e2e_test

import (
	"fmt"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func flatElements(element string) string {
	return strings.TrimSuffix(strings.Repeat(element+", ", 1100), ", ")
}

func TestLargeFlatLiteralSemantics(t *testing.T) {
	source := `import List from "@std/collections.ms"
import panic from "@std/faults.ms"
type Box:
    value: Int
fn tick(box: Box) -> Int:
    box.value = box.value + 1
    return box.value
`
	for _, fn := range []struct{ name, params, typ, element string }{
		{"boxes", "", "Box", "Box(0)"},
		{"references", "box: Box", "Box", "box"},
		{"nested", "", "List[Int]", "[1]"},
		{"floats", "", "Float", "-0.0, -1.25, 5e-324"},
		{"strings", "", "String", `"λ\nquote: \""`},
		{"interpolated", "box: Box", "String", `"{tick(box)}"`},
		{"effects", "box: Box", "Int", "tick(box)"},
		{"generic[T]", "value: T", "T", "value"},
	} {
		source += fmt.Sprintf("fn %s(%s) -> List[%s]:\n    return [%s]\n", fn.name, fn.params, fn.typ, flatElements(fn.element))
	}
	source += "fn defaults(values: List[Int] = [" + flatElements("7") + "]) -> List[Int]: values\n"
	source += `test "flat literal behavior":
    let a = boxes()
    let b = boxes()
    let alias = a
    let copy = a.clone()
    a.at(0).unwrap().value = 9
    if alias.at(0).unwrap().value != 9 or copy.at(0).unwrap().value != 9:
        return panic("shallow aliases changed")
    if a.at(1).unwrap().value != 0 or b.at(0).unwrap().value != 0:
        return panic("mutable objects were hoisted")
    let shared = Box(1)
    let refs = references(shared)
    shared.value = 12
    if refs.at(0).unwrap().value != 12 or refs.at(1099).unwrap().value != 12:
        return panic("element references were cloned")
    let children = nested()
    children.at(0).unwrap().append(9)
    if children.at(1).unwrap().length() != 1 or nested().at(0).unwrap().length() != 1:
        return panic("nested mutable storage was hoisted")
    let numbers = floats()
    if "{1.0 / numbers.at(0).unwrap()}" != "-Infinity":
        return panic("negative zero changed")
    if numbers.at(1).unwrap() != -1.25 or numbers.at(2).unwrap() != 5e-324:
        return panic("floating literals changed")
    if strings().at(1099).unwrap() != "λ\nquote: \"":
        return panic("literal string escaping changed")
    let counter = Box(0)
    let values = effects(counter)
    if counter.value != 1100 or values.at(255).unwrap() != 256 or values.at(256).unwrap() != 257 or values.at(1099).unwrap() != 1100:
        return panic("element evaluation order changed")
    counter.value = 0
    let texts = interpolated(counter)
    if counter.value != 1100 or texts.at(256).unwrap() != "257":
        return panic("interpolation was hoisted")
    let generic_values = generic(shared)
    shared.value = 21
    if generic_values.at(1099).unwrap().value != 21:
        return panic("generic identity changed")
    let first_default = defaults()
    first_default.with_value(index: 0, value: 99)
    if defaults().at(0).unwrap() != 7:
        return panic("default evaluations share storage")
`
	// Capture a plain local before a later match mutates it, within and across
	// chunks. The old single Go composite read the local after the mutation;
	// this explicitly verifies the source's left-to-right contract.
	source += `test "plain local before effectful element":
    var original = 7
    let selected: Optional[Int] = some(0)
    let values = [original, (match selected:
        some(value):
            original = 9
            value
        none: 0
    ), ` + flatElements("1") + `]
    if values.at(0).unwrap() != 7 or original != 9:
        return panic("earlier local was captured after a later mutation")
    original = 7
    let across = [` + strings.Repeat("original, ", 256) + `(match selected:
        some(value):
            original = 11
            value
        none: 0
    ), ` + flatElements("original") + `]
    if across.at(255).unwrap() != 7 or across.at(257).unwrap() != 11:
        return panic("element order across chunk boundary changed")
`
	result := compiler.CompileSource("flat-semantics.ms", source, compiler.Options{Tests: true})
	data, err := execute(t, result)
	if err != nil || !strings.Contains(string(data), "2 tests, 0 failed") {
		t.Fatalf("flat literal semantics: %v\n%s", err, data)
	}
}

func TestLargeFlatLiteralFaultLocation(t *testing.T) {
	source := `import List from "@std/collections.ms"
fn fail() -> Int:
    return 1 / 0
export fn main() -> Int:
    let values = [` + flatElements("1") + `,
        fail()
    ]
    return values.length()
`
	result := compiler.CompileSource("flat-fault.ms", source, compiler.Options{Entry: true})
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
	want := "flat-fault.ms:3:14 in fail\nflat-fault.ms:6:9 in main"
	if strings.Join(frames, "\n") != want {
		t.Fatalf("frames = %q, want %q; transcript:\n%s", frames, want, data)
	}
}

func TestLargeFlatLiteralControlFlow(t *testing.T) {
	prefix := `import List from "@std/collections.ms"
import panic from "@std/faults.ms"
import Closeable from "@std/cleanup.ms"
type Box:
    value: Int
type Resource:
    box: Box
impl Closeable for Resource:
    fn close() -> Unit:
        self.box.value = self.box.value + 1
fn tick(box: Box) -> Int:
    box.value = box.value + 100
    return box.value
fn failure() -> Result[Int, String]: error("expected")
fn propagate(box: Box) -> Result[Int, String]:
    with resource = Resource(box):
        let values = [` + flatElements("0") + `, try failure(), tick(box)]
        return ok(values.length())
fn early(box: Box) -> Int:
    let selected: Optional[Int] = some(42)
    let values = [`
	source := prefix + flatElements("0") + `, (match selected:
        some(value):
            with resource = Resource(box):
                return value
        none: 0
    ), tick(box)]
    return values.length()
test "return and cleanup across literal helpers":
    let box = Box(0)
    if early(box) != 42 or box.value != 1:
        return panic("source return or cleanup ownership changed")
    box.value = 0
    match propagate(box):
        ok(value): return panic("error did not propagate")
        error(message):
            if message != "expected" or box.value != 1:
                return panic("try propagation or cleanup ownership changed")
test "loop exits across literal helpers":
    let box = Box(0)
    var total = 0
    for number in [1, 2, 3]:
        let selected: Optional[Int] = some(number)
        let values = [` + flatElements("0") + `, (match selected:
            some(value):
                with resource = Resource(box):
                    if value == 1: continue
                    if value == 3: break
                value
            none: 0
        )]
        total = total + values.at(1100).unwrap()
    if total != 2 or box.value != 3:
        return panic("loop exit or cleanup ownership changed")
`
	result := compiler.CompileSource("flat-control.ms", source, compiler.Options{Tests: true})
	data, err := execute(t, result)
	if err != nil || !strings.Contains(string(data), "2 tests, 0 failed") {
		t.Fatalf("flat literal control flow: %v\n%s", err, data)
	}
}
