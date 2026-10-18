package compiler_test

import (
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"strings"
	"testing"
)

const recordCellSource = `interface Counter:
    fn bump(by: Int) Int
    fn lower(by: Int) Int
type Cell:
    total: Int
impl Counter for Cell:
    fn bump(by: Int) Int:
        self.total += by
        return self.total
    fn lower(by: Int) Int:
        self.total -= by
        return self.total
fn take(value: Cell) Int: return value.total
`

func TestClosedRecordIntBounds(t *testing.T) {
	for _, tc := range []struct {
		name, prefix, body string
		unchecked          bool
	}{
		{"induction", "let cell = Cell(0)", "cell.bump(1)\n        i += 1", true},
		{"subtract", "let cell = Cell(0)", "cell.lower(1)\n        i += 1", true},
		{"conditional", "let cell = Cell(0)", "if flag:\n            cell.bump(1)\n        i += 1", true},
		{"unknown", "let cell = Cell(0)", "cell.bump(value)\n        i += 1", false},
		{"overflow", "let cell = Cell(9223372036854775807)", "cell.bump(1)\n        i += 1", false},
		{"prefix", "let cell = Cell(9223372036854775807)", "cell.bump(1)\n        cell.lower(1)\n        i += 1", false},
		{"self", "let cell = Cell(1)", "cell.bump(cell.total)\n        i += 1", false},
		{"peer", "let cell = Cell(0)\n    let peer = Cell(0)", "cell.bump(peer.total)\n        peer.bump(1)\n        i += 1", false},
		{"scalar peer", "let cell = Cell(0)\n    var sum = 0", "cell.bump(sum)\n        sum += 1\n        i += 1", false},
		{"alias", "let cell = Cell(0)\n    let alias = cell", "cell.bump(1)\n        i += 1", false},
		{"returned alias", "let cell = Cell(0)\n    take(cell)", "cell.bump(1)\n        i += 1", false},
		{"capture", "let cell = Cell(0)\n    let read = fn() Int: cell.total", "cell.bump(1)\n        i += 1", false},
		{"bound method", "let cell = Cell(0)\n    let bump = cell.bump", "cell.bump(1)\n        i += 1", false},
		{"field reset", "let cell = Cell(0)", "cell.total = value\n        cell.bump(1)\n        i += 1", false},
		{"mutable binding", "var cell = Cell(0)", "cell.bump(1)\n        i += 1", false},
		{"result observed", "let cell = Cell(0)", "let result = cell.bump(1)\n        i += 1", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			source := recordCellSource + "fn probe(value: Int, flag: Bool) Int:\n    " + tc.prefix + "\n    var i = 0\n    while i < 1000:\n        " + tc.body + "\n    return cell.total\n"
			for _, kind := range []compiler.BuildType{compiler.Release, compiler.Debug} {
				r := compiler.CompileSource("records.ms", source, compiler.Options{BuildType: kind})
				if !r.Success() {
					t.Fatal(r.Diagnostics)
				}
				want := tc.unchecked && kind == compiler.Release
				if got := strings.Contains(r.Source, "cell.Total = cell.Total "); got != want {
					t.Fatalf("unchecked=%v want %v (%s):\n%s", got, want, kind, r.Source)
				}
			}
		})
	}
}

func TestClosedRecordRejectsDifferentMethodShapes(t *testing.T) {
	for _, method := range []string{
		"fn bump(by: Int = 1) Int:\n        self.total += by\n        return self.total",
		"fn bump(by: Int) Int:\n        self.total += by + 1\n        return self.total",
		"fn bump(by: Int) Int:\n        self.total += by\n        return by",
	} {
		source := "interface Counter:\n    fn bump(by: Int) Int\ntype Cell:\n    total: Int\nimpl Counter for Cell:\n    " + method + "\nfn probe() Int:\n    let cell = Cell(0)\n    var i = 0\n    while i < 1000:\n        cell.bump(1)\n        i += 1\n    return cell.total\n"
		r := compiler.CompileSource("records.ms", source, compiler.Options{})
		if !r.Success() {
			t.Fatal(r.Diagnostics)
		}
		if strings.Contains(r.Source, "cell.Total = cell.Total ") {
			t.Fatalf("expanded different method:\n%s", r.Source)
		}
	}
}

func TestClosedRecordGenericReceiverFallback(t *testing.T) {
	r := compiler.CompileSource("generic.ms", `interface Counter:
    fn bump(by: Int) Int
type Cell[T]:
    total: Int
impl Counter for Cell[T]:
    fn bump(by: Int) Int:
        self.total += by
        return self.total
fn probe() Int:
    let cell = Cell[String](0)
    var i = 0
    while i < 1000:
        cell.bump(1)
        i += 1
    return cell.total
`, compiler.Options{})
	if !r.Success() || strings.Contains(r.Source, "cell.Total = cell.Total ") {
		t.Fatalf("generic fallback: %v\n%s", r.Diagnostics, r.Source)
	}
}

func TestClosedRecordGenericCallerFallback(t *testing.T) {
	r := compiler.CompileSource("generic-caller.ms", recordCellSource+`fn count[T](value: T) Int:
    let cell = Cell(0)
    var i = 0
    while i < 1000:
        cell.bump(1)
        i += 1
    return cell.total
fn probe() Int: return count[String]("unused")
`, compiler.Options{})
	if !r.Success() || strings.Contains(r.Source, "cell.Total = cell.Total ") {
		t.Fatalf("generic caller fallback: %v\n%s", r.Diagnostics, r.Source)
	}
}
