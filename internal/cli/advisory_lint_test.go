package cli

import (
	"encoding/json"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/tooling"
)

func TestSafetyAdvisoriesDoNotBecomeCheckErrors(t *testing.T) {
	for _, tc := range []struct {
		name, source, code string
		line               int
	}{
		// manuscript:allow-nested-match CLI must keep check successful and report MSL107 via lint
		{"nested match", "fn use(value: Optional[Int]) Unit:\n    match value:\n        some(_):\n            match value:\n                some(_): unit\n                none: unit\n        none: unit\n", "MSL107", 4},
		{"pattern binding", "import filesystem from \"@std/fs.ms\"\nfn use(path: String) Int:\n    match filesystem().stat(path: path, follow_links: true):\n        error(NotFound): return 1\n        ok(_): return 0\n", "MSL106", 4},
		{"discarded result", "import {TextError} from \"@std/errors.ms\"\nfn fail() Result[Int, TextError]:\n    return error(TextError(\"boom\"))\nfn use() Unit:\n    fail()\n", "MSL104", 5},
		{"concurrent capture", "import network from \"@std/net.ms\"\nimport { HttpResponse } from \"@std/http.ms\"\nimport panic from \"@std/faults.ms\"\nfn use() Unit:\n    let shared = Map[Int, Int]()\n    let _server = network().serve(address: \"127.0.0.1:0\", handler: fn(request) HttpResponse:\n        shared.add(key: 1, value: 2)\n        return panic(\"unreached\")\n    )\n", "MSL105", 7},
	} {
		t.Run(tc.name, func(t *testing.T) {
			file := sourceFile(t, tc.source)
			if status, output, errors := invoke(t, "check", file); status != 0 || errors != "" {
				t.Fatalf("check: %d %s %s", status, output, errors)
			}
			status, output, errors := invoke(t, "lint", file, "--json")
			var result struct {
				Format      int                   `json:"format"`
				Diagnostics []tooling.LintFinding `json:"diagnostics"`
			}
			if status != 1 || errors != "" || json.Unmarshal([]byte(output), &result) != nil || result.Format != 1 {
				t.Fatalf("lint: %d %s %s", status, output, errors)
			}
			for _, issue := range result.Diagnostics {
				if issue.Code == tc.code && issue.Position.Line == tc.line {
					return
				}
			}
			t.Fatalf("missing %s at line %d: %+v", tc.code, tc.line, result.Diagnostics)
		})
	}
}
