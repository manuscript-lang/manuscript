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
	facts := factsOf(t, "fn a(n: Int) -> Int:\n    return b(n)\n\nfn b(n: Int) -> Int:\n    return a(n)\n")
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
