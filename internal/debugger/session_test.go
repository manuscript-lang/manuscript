package debugger

import (
	"strings"
	"testing"

	"github.com/go-delve/delve/service/api"
	"reflect"
)

func testNames() Names {
	return Names{
		Root:    "/work",
		Locals:  map[string]map[string]Local{"main": {"message": {Name: "message", Type: "String"}}},
		Sources: map[string]bool{"src/main.ms": true},
		Entities: []Entity{
			{Name: "Point", File: "src/main.ms", Line: 1},
			{Name: "main", File: "src/main.ms", Line: 4, Body: 5, Function: true},
			{Name: "helper", File: "src/main.ms", Line: 12, Body: 13, Function: true},
		},
	}
}

func TestNamesRelativeAndFunctionLookup(t *testing.T) {
	names := testNames()
	if got := names.relative("/work/src/main.ms"); got != "src/main.ms" {
		t.Fatalf("relative: %q", got)
	}
	if got := names.relative("./src/main.ms"); got != "src/main.ms" {
		t.Fatalf("relative dot path: %q", got)
	}
	if got := names.relative("/elsewhere/runtime.go"); got != "/elsewhere/runtime.go" {
		t.Fatalf("files outside the root keep their path: %q", got)
	}
	for line, want := range map[int]string{3: "", 4: "main", 9: "main", 12: "helper", 40: "helper", 1: ""} {
		if got := names.function("/work/src/main.ms", line); got != want {
			t.Errorf("function at line %d: %q, want %q", line, got, want)
		}
	}
	if got := names.function("/elsewhere/runtime.go", 10); got != "" {
		t.Errorf("a runtime file has no Manuscript function: %q", got)
	}
}

func TestNamesLocationAcceptsFileLinesAndFunctionNames(t *testing.T) {
	names := testNames()
	for spec, want := range map[string]string{
		"src/main.ms:7":   "/work/src/main.ms:7",
		"/abs/other.ms:2": "/abs/other.ms:2",
		"helper":          "/work/src/main.ms:13",
		"main":            "/work/src/main.ms:5",
	} {
		if got, err := names.location(spec); err != nil || got != want {
			t.Errorf("location(%q) = %q, %v; want %q", spec, got, err, want)
		}
	}
	for _, spec := range []string{"Point", "missing", "src/main.ms:0", "src/main.ms:x"} {
		if _, err := names.location(spec); err == nil || !strings.Contains(err.Error(), "file:line") {
			t.Errorf("location(%q) should explain the accepted forms: %v", spec, err)
		}
	}
	names.Entities = append(names.Entities, Entity{Name: "main", File: "src/other.ms", Line: 2, Body: 3, Function: true})
	if _, err := names.location("main"); err == nil || !strings.Contains(err.Error(), "ambiguous") {
		t.Errorf("duplicate function names should be ambiguous: %v", err)
	}
}

func TestRenderUnwrapsInterfaceScalars(t *testing.T) {
	wrapped := &api.Variable{Kind: reflect.Interface, Children: []api.Variable{{Kind: reflect.String, Value: "Arguments: 2\n"}}}
	if got := render(wrapped); got != "Arguments: 2\n" {
		t.Fatalf("interface string: %q", got)
	}
	if got := render(&api.Variable{Kind: reflect.Int64, Value: "3"}); got != "3" {
		t.Fatalf("int: %q", got)
	}
	if got := render(&api.Variable{Unreadable: "optimized out"}); !strings.Contains(got, "optimized out") {
		t.Fatalf("unreadable: %q", got)
	}
}

func TestEventTextHasNoPromptsOrEscapes(t *testing.T) {
	status := 0
	stop := Event{Event: "stop", Breakpoint: 1, Function: "main", File: "src/main.ms", Line: 7, Source: "    match x:", Stack: []Frame{{Function: "main", File: "src/main.ms", Line: 7}}, Locals: []Value{{Name: "message", Type: "String", Value: "hi\n"}}}
	text := stop.text()
	for _, want := range []string{"stopped (breakpoint 1) at main (src/main.ms:7)", "7:     match x:", "#0 main (src/main.ms:7)", `message: String = "hi\n"`} {
		if !strings.Contains(text, want) {
			t.Errorf("stop text missing %q:\n%s", want, text)
		}
	}
	if strings.Contains(text, "\x1b") || strings.Contains(text, "(dlv)") {
		t.Errorf("text must have no ANSI escapes or Delve prompts:\n%s", text)
	}
	if got := (Event{Event: "exit", Status: &status}).text(); got != "exited with status 0\n" {
		t.Errorf("exit text: %q", got)
	}
	if got := (Event{Event: "error", Message: "bad"}).text(); got != "error: bad\n" {
		t.Errorf("error text: %q", got)
	}
}
