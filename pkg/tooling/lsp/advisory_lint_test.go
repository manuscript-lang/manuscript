package lsp

import (
	"bufio"
	"bytes"
	"encoding/json"
	"io"
	"strings"
	"testing"
)

func TestSafetyAdvisoriesPublishAsWarnings(t *testing.T) {
	for _, tc := range []struct {
		name, source, code string
		line               int
	}{
		// manuscript:allow-nested-match editor warning must point at the inner match
		{"nested match", "fn use(value: Optional[Int]) -> Unit:\n    match value:\n        some(_):\n            match value:\n                some(_): unit\n                none: unit\n        none: unit\n", "MSL107", 3},
		{"pattern binding", "import filesystem from \"@std/fs.ms\"\nfn use(path: String) -> Int:\n    match filesystem().stat(path: path, follow_links: true):\n        error(NotFound): return 1\n        ok(_): return 0\n", "MSL106", 3},
		{"pattern binding CRLF and Unicode", "# café 🦀\r\nimport filesystem from \"@std/fs.ms\"\r\nfn use(path: String) -> Int:\r\n    match filesystem().stat(path: path, follow_links: true):\r\n        error(NotFound): return 1\r\n        ok(_): return 0\r\n", "MSL106", 4},
		{"discarded result", "fn fail() -> Result[Int, String]:\n    return error(\"boom\")\nfn use() -> Unit:\n    fail()\n", "MSL104", 3},
		{"concurrent capture", "import Map from \"@std/collections.ms\"\nimport TaskGroup from \"@std/tasks.ms\"\nfn use() -> Unit:\n    let shared = Map[Int, Int]()\n    with tasks = TaskGroup():\n        let _task = tasks.start(fn() -> Unit:\n            shared.add(key: 1, value: 2)\n        )\n", "MSL105", 6},
		{"prelude Map add concurrent capture", "import TaskGroup from \"@std/tasks.ms\"\nfn use() -> Unit:\n    let shared = Map[Int, Int]()\n    with tasks = TaskGroup():\n        let _task = tasks.start(fn() -> Unit:\n            shared.add(key: 1, value: 2)\n        )\n", "MSL105", 5},
	} {
		t.Run(tc.name, func(t *testing.T) {
			d := document{"file:///tmp/advisory.ms", tc.source, 1}
			input := frame("textDocument/didOpen", nil, map[string]any{"textDocument": d}) + frame("shutdown", 1, nil) + frame("exit", nil, nil)
			var output bytes.Buffer
			if err := Serve(strings.NewReader(input), &output); err != nil {
				t.Fatal(err)
			}
			reader := bufio.NewReader(&output)
			found := false
			for {
				body, err := readFrame(reader)
				if err == io.EOF {
					break
				}
				if err != nil {
					t.Fatal(err)
				}
				var message struct {
					Method string `json:"method"`
					Params struct {
						Diagnostics []struct {
							Code     string `json:"code"`
							Severity int    `json:"severity"`
							Source   string `json:"source"`
							Range    span   `json:"range"`
						} `json:"diagnostics"`
					} `json:"params"`
				}
				if err := json.Unmarshal(body, &message); err != nil {
					t.Fatal(err)
				}
				if message.Method != "textDocument/publishDiagnostics" {
					continue
				}
				for _, diagnostic := range message.Params.Diagnostics {
					if diagnostic.Severity == 1 {
						t.Fatalf("advisory became an error: %+v", diagnostic)
					}
					if diagnostic.Code == tc.code {
						found = true
						if tc.code == "MSL106" && (diagnostic.Range.Start.Character != 14 || diagnostic.Range.End != (position{Line: tc.line, Character: 22})) {
							t.Fatalf("warning must cover only NotFound: %+v", diagnostic)
						}
						if diagnostic.Severity != 2 || diagnostic.Source != "manuscript-lint" || diagnostic.Range.Start.Line != tc.line {
							t.Fatalf("wrong advisory: %+v", diagnostic)
						}
						if tc.code == "MSL107" && (diagnostic.Range.Start.Character != 12 || diagnostic.Range.End.Line != tc.line || diagnostic.Range.End.Character != 17) {
							t.Fatalf("nested-match warning did not span the inner keyword: %+v", diagnostic.Range)
						}
					}
				}
			}
			if !found {
				t.Fatalf("missing %s warning", tc.code)
			}
		})
	}
}
