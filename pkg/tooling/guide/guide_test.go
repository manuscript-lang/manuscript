package guide

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

// The cheat sheet's complete program is the one claim a reader can copy verbatim.
func TestCheatsheetProgramChecks(t *testing.T) {
	_, after, found := strings.Cut(Cheatsheet(), "<!-- complete -->\n```manuscript\n")
	if !found {
		t.Fatal("cheat sheet lost its complete program")
	}
	source, _, _ := strings.Cut(after, "```")
	result := compiler.CompileSource("cheatsheet.ms", source, compiler.Options{Entry: true, Tests: true, AnalyzeOnly: true})
	for _, issue := range result.Diagnostics {
		t.Errorf("cheat sheet program: %v", issue)
	}
}

// Agents read the guide every session, so its size is part of the contract.
func TestCheatsheetStaysShort(t *testing.T) {
	if n := len(Cheatsheet()); n > 2500 {
		t.Errorf("cheat sheet is %d bytes; keep it under 2500", n)
	}
}

// Each cheat-sheet claim a reader might get wrong is checked against the compiler.
func TestCheatsheetClaimsMatchTheCompiler(t *testing.T) {
	check := func(body string) []string {
		source := "export fn main() Int:\n" + body + "    return 0\n"
		var issues []string
		for _, issue := range compiler.CompileSource("claim.ms", source, compiler.Options{Entry: true, AnalyzeOnly: true}).Diagnostics {
			issues = append(issues, issue.Message)
		}
		return issues
	}
	accepted := []string{
		"    let a = [1, 2]\n",
		"    let m = Map[String, Int]()\n    let s = Set[Int]()\n",
		"    var n = 1\n    n = 2\n",
		"    var n = 1\n    n += 2\n    n %= 2\n",
		"    let o: Optional[Int] = none\n    let v = o.get(3)\n",
		"    let name = \"x\"\n    let text = \"hi {name}\"\n",
	}
	for _, body := range accepted {
		if issues := check(body); len(issues) > 0 {
			t.Errorf("claim should check clean:\n%s%v", body, issues)
		}
	}
	rejected := []string{
		"    let n = 1\n    n = 2\n",
		"    let a = [1, \"x\"]\n",
		"    let x = none\n",
		"    let a = 1\n  let b = 2\n",
	}
	for _, body := range rejected {
		if len(check(body)) == 0 {
			t.Errorf("claim should be rejected:\n%s", body)
		}
	}
	impl := "type T:\n    a: Int\n\nimpl T:\n    fn f(self) Int:\n        return 1\n\nexport fn main() Int:\n    return 0\n"
	if len(compiler.CompileSource("claim.ms", impl, compiler.Options{Entry: true, AnalyzeOnly: true}).Diagnostics) == 0 {
		t.Error("`impl T:` should be rejected")
	}
}

// Agents read these pages whole, so every page of the real library must fit its budget.
func TestStdPagesStayBounded(t *testing.T) {
	if n := len(Index()); n > 3500 {
		t.Errorf("index is %d bytes", n)
	}
	for _, m := range modules() {
		name := shortName(m.Path)
		page, err := Page(name)
		if err != nil || len(page) > pageBudget || strings.Count(page, "\n") > moduleLines+4 {
			t.Errorf("Page(%q): %d bytes, %d lines, %v", name, len(page), strings.Count(page, "\n"), err)
		}
		for _, d := range m.Declarations {
			path := name + "." + bare(d.Name)
			page, err := Page(path)
			if err != nil || len(page) > pageBudget+200 {
				t.Errorf("Page(%q): %d bytes, %v", path, len(page), err)
			}
			for _, member := range d.Members {
				page, err := Page(path + "." + bare(member.Name))
				if err != nil || len(page) > 3*(300+800+200)+pageBudget/2 {
					t.Errorf("Page(%q): %d bytes, %v", path+"."+member.Name, len(page), err)
				}
			}
		}
	}
}

func TestStdPagesResolveForms(t *testing.T) {
	for _, path := range []string{"json", "@std/json.ms", "json.parse", "@std/json.ms.parse", "prelude.List", "prelude.List.sorted", "prelude.List.group_by"} {
		page, err := Page(path)
		if err != nil || page == "" {
			t.Errorf("Page(%q) = %.60q, %v", path, page, err)
		}
	}
	if page, _ := Page("json"); !strings.Contains(page, `import Name from "@std/json.ms"`) {
		t.Errorf("module page lacks import hint: %q", page)
	}
	for _, path := range []string{"nope", "json.nope", "prelude.List.nope"} {
		_, err := Page(path)
		if err == nil || len(err.Error()) > 700 {
			t.Errorf("Page(%q) error = %v", path, err)
		}
	}
	index := Index()
	if !strings.Contains(index, "json ") || !strings.HasPrefix(strings.SplitN(index, "\n\n", 2)[1], "prelude") {
		t.Errorf("index = %.200q", index)
	}
	if names := ModuleNames(); len(names) < 20 || !contains(names, "json") || names[0] != "prelude" {
		t.Errorf("module names = %v", names)
	}
}

func TestSearchOutputStaysBounded(t *testing.T) {
	for _, query := range []string{"list", "read", "file", "string", "parse", "a", "map set"} {
		if text := FormatMatches(query, Search(query, 15)); len(text) > searchBudget+100 {
			t.Errorf("search %q output is %d bytes", query, len(text))
		}
	}
}

func contains(list []string, want string) bool {
	for _, item := range list {
		if item == want {
			return true
		}
	}
	return false
}
