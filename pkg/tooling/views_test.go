package tooling

import (
	"strings"
	"testing"
)

func TestViewsAnswerOneQuestionEach(t *testing.T) {
	facts := factsOf(t, reviewBase)
	cases := []struct {
		view, entity string
		want         []string
		absent       []string
	}{
		{"effects", "say", []string{"EFFECTS VIEW", "`- say  effects:", "@std/io.ms#stdout"}, nil},
		{"errors", "", []string{"say  error: Error, try sites: 1"}, []string{"add"}},
		{"calls", "run", []string{"run  [fn] r.ms:", "add  [fn]"}, []string{"say"}},
		{"modules", "", []string{"r.ms", "@std/io.ms"}, nil},
	}
	for _, c := range cases {
		node, err := BuildView(facts, c.view, c.entity, 0)
		if err != nil {
			t.Fatalf("%s: %v", c.view, err)
		}
		text := node.ASCII()
		for _, w := range c.want {
			if !strings.Contains(text, w) {
				t.Errorf("%s lacks %q:\n%s", c.view, w, text)
			}
		}
		for _, w := range c.absent {
			if strings.Contains(text, w) {
				t.Errorf("%s should not contain %q:\n%s", c.view, w, text)
			}
		}
		if again, _ := BuildView(facts, c.view, c.entity, 0); again.ASCII() != text || again.Mermaid() != node.Mermaid() {
			t.Errorf("%s is not deterministic", c.view)
		}
	}
}

func TestViewDepthCycleAndErrors(t *testing.T) {
	facts := factsOf(t, "fn a(n: Int) Int:\n    return b(n)\n\nfn b(n: Int) Int:\n    return a(n)\n")
	node, err := BuildView(facts, "calls", "a", 5)
	if err != nil || !strings.Contains(node.ASCII(), "a  (cycle)") {
		t.Fatalf("%v\n%s", err, node.ASCII())
	}
	shallow, _ := BuildView(facts, "calls", "a", 1)
	if strings.Contains(shallow.ASCII(), "(cycle)") || !strings.Contains(shallow.ASCII(), "b  [fn]") {
		t.Fatalf("depth 1:\n%s", shallow.ASCII())
	}
	if _, err := BuildView(facts, "calls", "missing", 0); err == nil || !strings.Contains(err.Error(), "no entity named missing") {
		t.Fatalf("err = %v", err)
	}
	if mermaid := node.Mermaid(); !strings.HasPrefix(mermaid, "flowchart TD\n    n0[") {
		t.Fatal(mermaid)
	}
}

const flowSource = `import stdout from "@std/io.ms"

fn load(n: Int) Result[Int, Error]:
    if n > 3:
        return ok(0)
    return ok(n)

fn guarded(n: Int) Result[Int, Error]:
    with out = stdout():
        let v = try load(n)
        if v > 1:
            return ok(2)
    return ok(0)

export fn main() Int:
    match guarded(1):
        ok(_): return 0
        error(_): return 1
`

func TestFlowViewOutlinesSignificantSteps(t *testing.T) {
	facts := factsOf(t, flowSource)
	node, err := BuildView(facts, "flow", "main", 2)
	if err != nil {
		t.Fatal(err)
	}
	want := "FLOW VIEW\n" +
		"`- main  [fn] r.ms:15\n" +
		"   |- call guarded\n" +
		"   |  |- with out = stdout()  [closed on exit]\n" +
		"   |  |  |- native @std/io.ms#stdout\n" +
		"   |  |  |- try call load\n" +
		"   |  |  `- if v > 1\n" +
		"   |  |     `- return ok(2)\n" +
		"   |  `- return ok(0)\n" +
		"   `- match guarded(1)\n" +
		"      |- ok(_): return 0\n" +
		"      `- error(_): return 1\n"
	if got := node.ASCII(); got != want {
		t.Fatalf("got:\n%s\nwant:\n%s", got, want)
	}
}

func TestScopeViewKeepsCleanupScopesAndTheirExits(t *testing.T) {
	node, err := BuildView(factsOf(t, flowSource), "scope", "guarded", 0)
	if err != nil {
		t.Fatal(err)
	}
	want := "SCOPE VIEW\n" +
		"`- guarded  [fn] r.ms:8\n" +
		"   `- with out = stdout()  [closed on exit]\n" +
		"      |- try call load\n" +
		"      `- if v > 1\n" +
		"         `- return ok(2)\n"
	if got := node.ASCII(); got != want {
		t.Fatalf("got:\n%s\nwant:\n%s", got, want)
	}
	if _, err := BuildView(factsOf(t, flowSource), "flow", "", 0); err == nil || !strings.Contains(err.Error(), "needs --entity") {
		t.Fatalf("err = %v", err)
	}
}
