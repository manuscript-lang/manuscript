package tooling

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

const patternCaptureSource = "type Failure:\n    case NotFound\n    case Denied(reason: String)\nfn classify(result: Result[Int, Failure]) -> Int:\n    match result:\n        error(NotFound): return 1\n        ok(value): return value\n"

func TestPatternBindingAdvisory(t *testing.T) {
	cases := []struct {
		name, source string
		messages     []string
	}{
		{"nullary payload case", patternCaptureSource, []string{"NotFound is a case of Failure", "fresh binding for every Failure payload", "error(payload):", "match payload:", "NotFound:", "lowercase binding name if intentional", "separate helper"}},
		{"read does not turn binding into case", strings.Replace(patternCaptureSource, "return 1", "return NotFound.toString().byte_length()", 1), []string{"NotFound is a case of Failure"}},
		{"payload case with fields", strings.Replace(patternCaptureSource, "error(NotFound)", "error(Denied)", 1), []string{"Denied is a case of Failure", "Denied(_):"}},
		{"multiple payload fields", "type Failure:\n    case NotFound\n    case Denied\ntype Envelope:\n    case Pair(left: Failure, right: Failure)\nfn use(value: Envelope) -> Int:\n    match value:\n        Pair(payload, NotFound): return 1\n", []string{"Pair(payload, payload2):", "match payload2:", "NotFound:"}},
		{"record constructor", "type Item:\n    value: Int\nfn use(value: Optional[Item]) -> Int:\n    match value:\n        some(Item): return Item.value\n        none: return 0\n", []string{"Item is a type name", "fresh binding for every Item payload", "lowercase binding name if intentional"}},
		{"alternative type name", strings.Replace(patternCaptureSource, "error(NotFound)", "error(Failure)", 1), []string{"Failure is a type name"}},
		{"primitive type name", "fn use(value: Optional[Int]) -> Int:\n    match value:\n        some(Int): return Int\n        none: return 0\n", []string{"Int is a type name"}},
		{"visible unrelated case", "type Flag:\n    case Ready\nfn use(value: Optional[Int]) -> Int:\n    match value:\n        some(Ready): return Ready\n        none: return 0\n", []string{"Ready is a case of Flag", "fresh binding for every Int payload"}},
		{"ambiguous visible case", "type First:\n    case Ready\ntype Second:\n    case Ready\nfn use(value: Optional[Int]) -> Int:\n    match value:\n        some(Ready): return Ready\n        none: return 0\n", []string{"Ready is a visible alternative case name"}},
		{"generic payload application", "type Failure[T]:\n    case NotFound\n    case Denied(reason: T)\nfn use[T](value: Result[Int, Failure[T]]) -> Int:\n    match value:\n        error(NotFound): return 1\n        ok(value): return value\n", []string{"NotFound is a case of Failure[T]", "fresh binding for every Failure[T] payload", "match payload:"}},
		{"contract receiver", "interface Describe:\n    fn describe() -> String\ntype State:\n    case Ready\n    case Waiting\nimpl Describe for State:\n    fn describe() -> String: \"state\"\nfn use(value: Describe) -> Int:\n    match value:\n        State(Ready): return 1\n        _: return 0\n", []string{"Ready is a case of State", "State(payload):", "Ready:"}},
		{"generic record constructor", "type Box[T]:\n    value: T\nfn use[T](value: Optional[Box[T]]) -> T:\n    match value:\n        some(Box): return Box.value\n        none: return panic(message: \"empty\")\n", []string{"Box is a type name", "every Box[T] payload"}},
		{"owning type shadow", "type Flag:\n    case Ready\nfn use(value: Optional[Int]) -> Int:\n    let Flag = 2\n    match value:\n        some(Ready): return Ready\n        none: return 0\n", nil},
		{"qualified outer pattern", strings.Replace(patternCaptureSource, "error(NotFound)", "Result[Int, Failure].error(NotFound)", 1), []string{"error(payload):"}},
		{"unknown capitalized binder", strings.Replace(patternCaptureSource, "error(NotFound)", "error(Cause)", 1), nil},
		{"intentional lowercase binder", strings.Replace(patternCaptureSource, "error(NotFound)", "error(cause)", 1), nil},
		{"intentional underscore binder", strings.Replace(patternCaptureSource, "error(NotFound)", "error(_NotFound)", 1), nil},
		{"placeholder", strings.Replace(patternCaptureSource, "error(NotFound)", "error(_)", 1), nil},
		{"lowercase case spelling", strings.ReplaceAll(patternCaptureSource, "NotFound", "missing"), nil},
		{"parameter shadow", strings.Replace(patternCaptureSource, "classify(result:", "classify(NotFound: Int, result:", 1), nil},
		{"local value shadow", strings.Replace(patternCaptureSource, "    match result:", "    let NotFound = 2\n    match result:", 1), nil},
		{"function shadow", "fn NotFound() -> Int: 2\n" + patternCaptureSource, nil},
		{"type variable shadow", strings.Replace(patternCaptureSource, "fn classify(", "fn classify[NotFound](", 1), nil},
		{"ordinary binding", "type Failure:\n    case NotFound\nfn use() -> Int:\n    let NotFound = 1\n    return NotFound\n", nil},
		{"generic unknown binder", "fn use[T](value: Optional[T]) -> T:\n    match value:\n        some(Value): return Value\n        none: return panic(message: \"empty\")\n", nil},
		{"separate payload helper", "type Failure:\n    case NotFound\n    case Denied(reason: String)\nfn failure_code(cause: Failure) -> Int:\n    match cause:\n        NotFound: return 1\n        Denied(_): return 2\nfn classify(result: Result[Int, Failure]) -> Int:\n    match result:\n        error(cause): return failure_code(cause)\n        ok(value): return value\n", nil},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			source := tc.source
			if strings.Contains(source, "panic(") {
				source = "import panic from \"@std/faults.ms\"\n" + source
			}
			checked := compiler.CompileSource("patterns.ms", source, compiler.Options{AnalyzeOnly: true})
			if !checked.Success() {
				t.Fatal(checked.Diagnostics)
			}
			var findings []LintFinding
			for _, finding := range LintProgram(checked.Program) {
				if finding.Code == "MSL106" {
					findings = append(findings, finding)
				}
			}
			if len(tc.messages) == 0 {
				if len(findings) != 0 {
					t.Fatal(findings)
				}
				return
			}
			if len(findings) != 1 {
				t.Fatal(findings)
			}
			for _, text := range tc.messages {
				if !strings.Contains(findings[0].Message, text) {
					t.Fatalf("missing %q in %s", text, findings[0].Message)
				}
			}
			if strings.Contains(findings[0].Message, "fresh binding for every Int") && strings.Contains(findings[0].Message, "match payload:") {
				t.Fatal("suggested matching an unrelated primitive payload", findings)
			}
		})
	}
}

func TestPatternBindingPositions(t *testing.T) {
	for _, newline := range []string{"\n", "\r\n"} {
		source := strings.ReplaceAll("# café 🦀\n"+patternCaptureSource, "\n", newline)
		checked := compiler.CompileSource("range.ms", source, compiler.Options{AnalyzeOnly: true})
		if !checked.Success() {
			t.Fatal(checked.Diagnostics)
		}
		found := false
		for _, finding := range LintProgram(checked.Program) {
			if finding.Code != "MSL106" {
				continue
			}
			found = true
			offset := strings.Index(source, "error(NotFound)") + len("error(")
			if finding.Position.File != "range.ms" || finding.Position.Offset != offset || finding.Position.Line != 7 || finding.Position.Column != 15 {
				t.Fatalf("wrong binding position: %+v", finding)
			}
			if source[offset:offset+len("NotFound")] != "NotFound" {
				t.Fatal("wrong token range")
			}
		}
		if !found {
			t.Fatal("missing binding warning")
		}
	}
}

func TestImportedPatternNamesAndAliases(t *testing.T) {
	root := t.TempDir()
	files := map[string]string{
		"ms.toml":   "[project]\nname = \"pattern-hints\"\nsource = \".\"\nentry = \"main.ms\"\n[aliases]\n\"@domain\" = \"./domain.ms\"\n",
		"domain.ms": "export type Failure:\n    case NotFound\n    case Denied(reason: String)\nexport type Item:\n    value: Int\nexport fn fail() -> Result[Int, Failure]: error(Failure.Denied(\"denied\"))\n",
	}
	for name, source := range files {
		if err := os.WriteFile(filepath.Join(root, name), []byte(source), 0600); err != nil {
			t.Fatal(err)
		}
	}
	for _, path := range []string{"./domain.ms", "@domain"} {
		source := "import { Failure, Item, fail } from \"" + path + "\"\nfn use() -> Int:\n    match fail():\n        error(NotFound): return 1\n        ok(value): return value\nfn record(value: Optional[Item]) -> Int:\n    match value:\n        some(Item): return Item.value\n        none: return 0\n"
		if err := os.WriteFile(filepath.Join(root, "main.ms"), []byte(source), 0600); err != nil {
			t.Fatal(err)
		}
		checked := compiler.CompileFile(filepath.Join(root, "ms.toml"), compiler.Options{AnalyzeOnly: true})
		if !checked.Success() {
			t.Fatal(checked.Diagnostics)
		}
		var findings []LintFinding
		for _, finding := range LintProgram(checked.Program) {
			if finding.Code == "MSL106" {
				findings = append(findings, finding)
			}
		}
		if len(findings) != 2 || findings[0].Position.File != "main.ms" || !strings.Contains(findings[0].Message, "case of Failure") || !strings.Contains(findings[1].Message, "Item is a type name") {
			t.Fatal(findings)
		}
	}
}

func TestInferredStandardErrorPayload(t *testing.T) {
	source := "import filesystem from \"@std/fs.ms\"\nfn classify(path: String) -> String:\n    match filesystem().stat(path: path, follow_links: true):\n        error(NotFound): return \"missing\"\n        ok(_): return \"exists\"\n"
	checked := compiler.CompileSource("filesystem.ms", source, compiler.Options{AnalyzeOnly: true})
	if !checked.Success() {
		t.Fatal(checked.Diagnostics)
	}
	findings := LintProgram(checked.Program)
	if len(findings) != 1 || findings[0].Code != "MSL106" || !strings.Contains(findings[0].Message, "NotFound is a case of FileSystemError") {
		t.Fatal(findings)
	}
}
