package compiler

import "testing"

// A module-level constant may name a payloadless case of a type declared after
// it; declaration order of constants and types must not matter.
func TestConstantMayNameCaseOfLaterType(t *testing.T) {
	source := `let initial = Mode.Idle

type Mode:
    case Idle
    case Busy

export fn main() -> Int:
    match initial:
        Idle:
            return 0
        Busy:
            return 1
`
	result := CompileSource("order.ms", source, Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	if result.Source == "" {
		t.Fatal("no generated source")
	}
}
