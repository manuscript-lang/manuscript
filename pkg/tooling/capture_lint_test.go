package tooling

import (
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestCaptureLintHandlerMutations(t *testing.T) {
	prefix := `import network from "@std/net.ms"
import { HttpResponse } from "@std/http.ms"
import panic from "@std/faults.ms"
`
	cases := []struct {
		name, body string
		count      int
	}{
		{"map update", `    let values = {"hits": 0}
    let _server = network().serve(address: "127.0.0.1:0", handler: fn(request) HttpResponse:
        values.add(key: "hits", value: 1)
        return panic("not executed by lint")
    )
`, 1},
		{"list update", `    let values = [0]
    let _server = network().serve(address: "127.0.0.1:0", handler: fn(request) HttpResponse:
        values.append(1)
        return panic("not executed by lint")
    )
`, 1},
		{"read only", `    let values = {"hits": 0}
    let _server = network().serve(address: "127.0.0.1:0", handler: fn(request) HttpResponse:
        values.get("hits")
        return panic("not executed by lint")
    )
`, 0},
		{"local mutation", `    let _server = network().serve(address: "127.0.0.1:0", handler: fn(request) HttpResponse:
        let values = [1]
        values.append(2)
        return panic("not executed by lint")
    )
`, 0},
		{"clone mutation", `    let values = [0]
    let _server = network().serve(address: "127.0.0.1:0", handler: fn(request) HttpResponse:
        values.clone().append(2)
        return panic("not executed by lint")
    )
`, 0},
		{"unrelated nested closure", `    let values = [0]
    let _server = network().serve(address: "127.0.0.1:0", handler: fn(request) HttpResponse:
        let _later = fn(): values.append(1)
        return panic("not executed by lint")
    )
`, 0},
		{"sequential closure", `    let values = [0]
    let operation = fn(): values.append(1)
    let _result = operation()
`, 0},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			checked := compiler.CompileSource("capture.ms", prefix+"fn run() Unit:\n"+tc.body, compiler.Options{AnalyzeOnly: true})
			if !checked.Success() {
				t.Fatal(checked.Diagnostics)
			}
			findings := lintSharedCaptures(checked.Program)
			if len(findings) != tc.count {
				t.Fatalf("got %v, want %d findings", findings, tc.count)
			}
			for _, finding := range findings {
				if finding.Code != "MSL105" || finding.Position.File != "capture.ms" {
					t.Fatal(finding)
				}
			}
		})
	}
}

func TestConcurrentCaptureLintDoesNotGuessMethodNames(t *testing.T) {
	source := `interface Starter:
    fn start(operation: fn() Unit) Unit
type Sequential:
impl Starter for Sequential:
    fn start(operation: fn() Unit) Unit:
        operation()
fn run() Unit:
    let values = [0]
    Sequential().start(fn():
        values.append(1)
    )
`
	checked := compiler.CompileSource("capture.ms", source, compiler.Options{AnalyzeOnly: true})
	if !checked.Success() {
		t.Fatal(checked.Diagnostics)
	}
	if findings := lintSharedCaptures(checked.Program); len(findings) != 0 {
		t.Fatal(findings)
	}
}

func TestConcurrentCaptureLintHTTPHandlers(t *testing.T) {
	prefix := `import network from "@std/net.ms"
import { HttpResponse, HttpServerOptions } from "@std/http.ms"
import panic from "@std/faults.ms"
fn run() Unit:
    let values = [0]
`
	for _, body := range []string{
		`    let _server = network().serve(address: "127.0.0.1:0", handler: fn(request) HttpResponse:
        values.append(1)
        return panic("not executed by lint")
    )
`,
		`    let _server = network().serve_stream(address: "127.0.0.1:0", handler: fn(exchange):
        values.append(1)
        return ok(unit)
    , options: HttpServerOptions(tls: none))
`,
	} {
		checked := compiler.CompileSource("capture.ms", prefix+body, compiler.Options{AnalyzeOnly: true})
		if !checked.Success() {
			t.Fatal(checked.Diagnostics)
		}
		if findings := lintSharedCaptures(checked.Program); len(findings) != 1 {
			t.Fatal(findings)
		}
	}
}
