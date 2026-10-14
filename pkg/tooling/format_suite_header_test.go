package tooling_test

import (
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
)

// A suite is indented relative to the last line of a multi-line header. The
// formatter collapses or moves that line back to the statement's indentation, so the suite
// has to move with it instead of making the output unparsable.
func TestFormatMovesSuiteWithMisindentedHeaderClose(t *testing.T) {
	for name, test := range map[string]struct{ source, want string }{
		"if": {
			"fn f() -> Int:\n    for mode in [1]:\n        if not (\n                mode == 2\n            ):\n                return 2\n    return 3\n",
			"fn f() -> Int:\n    for mode in [1]:\n        if not (mode == 2):\n            return 2\n\n    return 3\n",
		},
		"while with nested suite": {
			"fn f() -> Int:\n    while foo(\n            a\n        ):\n            if b:\n                return 1\n            return 2\n    return 3\n",
			"fn f() -> Int:\n    while foo(a):\n        if b:\n            return 1\n\n        return 2\n\n    return 3\n",
		},
		"else if": {
			"fn f() -> Int:\n    if a:\n        return 1\n    else if foo(\n            a\n        ):\n            return 2\n    return 3\n",
			"fn f() -> Int:\n    if a:\n        return 1\n    else if foo(a):\n        return 2\n\n    return 3\n",
		},
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := parser.Parse("input.ms", test.source); err != nil {
				t.Fatalf("input must be valid source: %v", err)
			}
			formatted, err := tooling.Format("input.ms", test.source)
			if err != nil || formatted != test.want {
				t.Fatalf("got %q, err %v, want %q", formatted, err, test.want)
			}
			twice, err := tooling.Format("input.ms", formatted)
			if err != nil || twice != formatted {
				t.Fatalf("formatting is not idempotent: %q, %v", twice, err)
			}
		})
	}
}
