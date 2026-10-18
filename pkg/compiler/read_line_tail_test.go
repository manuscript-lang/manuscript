package compiler_test

import (
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"strings"
	"testing"
)

func TestReadLinePresenceTailSelection(t *testing.T) {
	prefix := "import {read_line, ReadStream} from \"@std/io.ms\"\n"
	for _, tc := range []struct {
		name, body string
		selected   bool
	}{
		{"canonical", "if let line = read_line(input):\n        return line.is_some()\n    return false", true},
		{"explicit limit", "if let line = read_line(input, max_bytes: 100):\n        return line.is_some()\n    return false", true},
		{"else", "if let line = read_line(input):\n        return line.is_some()\n    else:\n        return false", false},
		{"different failure", "if let line = read_line(input):\n        return line.is_some()\n    return true", false},
		{"different observation", "if let line = read_line(input):\n        return line.is_none()\n    return false", false},
		{"payload observed", "if let line = read_line(input):\n        let size = line.get().byte_length()\n        return size > 0\n    return false", false},
		{"effect", "if let line = read_line(input):\n        visits.append(1)\n        return line.is_some()\n    return false", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			source := prefix + "fn probe(input: ReadStream, visits: List[Int]) Bool:\n    " + tc.body + "\n"
			for _, kind := range []compiler.BuildType{compiler.Release, compiler.Debug} {
				result := compiler.CompileSource("line.ms", source, compiler.Options{BuildType: kind})
				if !result.Success() {
					t.Fatal(result.Diagnostics)
				}
				want := tc.selected && kind == compiler.Release
				if got := strings.Contains(result.Source, "rt.Io_HasLine("); got != want {
					t.Fatalf("presence=%v want %v:\n%s", got, want, result.Source)
				}
			}
		})
	}
}

func TestReadLineCallableAliasFallback(t *testing.T) {
	result := compiler.CompileSource("alias.ms", `import {read_line, ReadStream} from "@std/io.ms"
fn probe(input: ReadStream) Bool:
    let next = read_line
    if let line = next(input):
        return line.is_some()
    return false
`, compiler.Options{})
	if !result.Success() || strings.Contains(result.Source, "rt.Io_HasLine(") {
		t.Fatalf("callable alias fallback: %v\n%s", result.Diagnostics, result.Source)
	}
}
