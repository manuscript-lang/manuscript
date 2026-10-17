package tooling

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func factsOf(t *testing.T, source string) Facts {
	t.Helper()
	result := compiler.CompileSource("r.ms", source, compiler.Options{AnalyzeOnly: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	return CollectFacts(result.Program)
}

func review(t *testing.T, base, head string, touched ...int) Report {
	t.Helper()
	input := DiffInput{Files: 1, Sources: 1, Added: map[string]bool{}, Touched: map[string][]int{"r.ms": touched}, BaseChecked: true}
	return DiffReport(factsOf(t, base), factsOf(t, head), input, ReviewOptions{})
}

const reviewBase = `import stdout from "@std/io.ms"

fn say(text: String) -> Result[Unit, Error]:
    try stdout().write("{text}\n".to_bytes())
    return stdout().flush()

fn add(a: Int, b: Int) -> Int:
    return a + b

export fn run() -> Int:
    return add(1, 2)
`

func TestReviewRanksEffectGainThroughCallers(t *testing.T) {
	head := strings.Replace(reviewBase, "    return a + b", "    say(\"adding\")\n    return a + b", 1)
	report := review(t, reviewBase, head, 8)
	text := report.Render("ascii")
	for _, want := range []string{"EFFECT+", "add", "effects: none ->", "run", "path: add -> say -> "} {
		if !strings.Contains(text, want) {
			t.Errorf("report lacks %q:\n%s", want, text)
		}
	}
	if len(report.Findings) < 2 || report.Findings[0].Tier != TierEffect {
		t.Fatalf("findings = %+v", report.Findings)
	}
}

func TestReviewNamesErrorFlowAndContractChanges(t *testing.T) {
	base := "export fn load(n: Int) -> Result[Int, String]:\n    return ok(n)\n"
	head := "export fn load(n: Int) -> Result[Int, Error]:\n    return ok(n)\n"
	text := review(t, base, head, 1).Render("ascii")
	for _, want := range []string{"CONTRACT", "ERROR", "error type: String -> Error"} {
		if !strings.Contains(text, want) {
			t.Errorf("report lacks %q:\n%s", want, text)
		}
	}
}

func TestReviewReportsOnlyInternalForABodyEdit(t *testing.T) {
	head := strings.Replace(reviewBase, "return a + b", "return b + a", 1)
	report := review(t, reviewBase, head, 8)
	if report.Result != "0 need attention, 1 internal" {
		t.Fatalf("result = %q\n%s", report.Result, report.Render("ascii"))
	}
}

func TestReviewOfIdenticalSourceHasNoChange(t *testing.T) {
	report := review(t, reviewBase, reviewBase)
	if report.Result != "no semantic change" || strings.Contains(report.Render("ascii"), "LOOK HERE FIRST\n   #") {
		t.Fatalf("%s", report.Render("ascii"))
	}
}

func TestReviewIsDeterministic(t *testing.T) {
	head := strings.Replace(reviewBase, "    return a + b", "    say(\"adding\")\n    return a + b", 1)
	first := review(t, reviewBase, head, 8)
	for i := 0; i < 5; i++ {
		again := review(t, reviewBase, head, 8)
		for _, format := range []string{"ascii", "markdown", "json"} {
			if first.Render(format) != again.Render(format) {
				t.Fatalf("%s output differs between runs", format)
			}
		}
	}
	if !strings.Contains(first.Render("ascii"), "digest sha256:") {
		t.Fatal("no digest")
	}
}

func TestProjectReportMapsPublicSurfaceAndEntryPoints(t *testing.T) {
	text := ProjectReport(factsOf(t, reviewBase), ReviewOptions{}).Render("ascii")
	for _, want := range []string{"PUBLIC SURFACE", "run", "ERROR TYPES", "Error", "@std/io.ms"} {
		if !strings.Contains(text, want) {
			t.Errorf("project report lacks %q:\n%s", want, text)
		}
	}
}

func TestReportCapsRowsUnlessAll(t *testing.T) {
	var base, head strings.Builder
	for i := 0; i < 8; i++ {
		base.WriteString("export fn f" + string(rune('a'+i)) + "() -> Int:\n    return 1\n\n")
		head.WriteString("export fn f" + string(rune('a'+i)) + "() -> String:\n    return \"x\"\n\n")
	}
	input := DiffInput{Files: 1, Sources: 1, Added: map[string]bool{}, Touched: map[string][]int{}, BaseChecked: true}
	capped := DiffReport(factsOf(t, base.String()), factsOf(t, head.String()), input, ReviewOptions{}).Render("ascii")
	if !strings.Contains(capped, "+3 more (use --all)") {
		t.Fatalf("not capped:\n%s", capped)
	}
	all := DiffReport(factsOf(t, base.String()), factsOf(t, head.String()), input, ReviewOptions{All: true}).Render("ascii")
	if strings.Contains(all, "more (use --all)") {
		t.Fatalf("--all still capped:\n%s", all)
	}
}

func TestDiagramASCIIIsAnOrderedOutline(t *testing.T) {
	result := compiler.CompileSource("d.ms", "fn one() -> Int:\n    return 1\n\nfn two() -> Int:\n    return one() + one()\n", compiler.Options{AnalyzeOnly: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	got := DiagramASCII(Inspect(result.Program))
	want := "CALL GRAPH\nd.ms::one [fn]\nd.ms::two [fn]\n  -> d.ms::one (function) x2\n"
	if got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}
