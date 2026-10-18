package lsp

import (
	"strings"
	"testing"
)

const groupSource = `let (
    LOW = 1
    HIGH: Int = LOW + 9
)

fn total() -> Int:
    var (
        sum = LOW
        extra = HIGH
    )
    sum += extra
    return sum
`

func TestBindingGroupHover(t *testing.T) {
	for _, item := range []struct{ needle, want string }{
		{"HIGH: Int", "HIGH: Int"},
		{"LOW + 9", "LOW: Int"},
		{"sum = LOW", "sum: Int"},
		{"extra\n", "extra: Int"},
		{"sum +=", "sum: Int"},
	} {
		_, _, hover := definitionAt(t, groupSource, strings.Index(groupSource, item.needle))
		if !strings.Contains(hover, item.want) {
			t.Errorf("%q: hover %q, want %q", item.needle, hover, item.want)
		}
	}
}
