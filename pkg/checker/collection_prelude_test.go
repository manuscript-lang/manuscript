package checker

import (
	"slices"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Walk checked signatures, including callbacks, fields, cases, generic bounds,
// native receiver requirements and support interfaces. Primitive APIs are leaves.
func TestCollectionPreludePublicTypeClosure(t *testing.T) {
	ensureStandard()
	seen := map[*Type]bool{}
	definitions := map[*Definition]bool{}
	names := map[string]bool{}
	var visit func(*Type)
	visit = func(typ *Type) {
		if typ == nil || seen[typ] {
			return
		}
		seen[typ] = true
		for _, arg := range typ.Args {
			visit(arg)
		}
		for _, bound := range typ.Bounds {
			visit(bound)
		}
		for _, param := range typ.Params {
			visit(param.Type)
		}
		visit(typ.Result)
		def := typ.Def
		if def == nil || definitions[def] {
			return
		}
		definitions[def] = true
		if !isPreludeSymbol(def.Symbol) {
			t.Errorf("public collection dependency needs the prelude: %s", def.Symbol.Name)
		}
		names[def.Symbol.Name] = true
		for _, variable := range def.Variables {
			visit(variable)
		}
		for _, field := range def.Fields {
			visit(field.Type)
		}
		for _, cs := range def.Cases {
			for _, field := range cs.Fields {
				visit(field.Type)
			}
		}
		for _, operation := range def.Operations {
			visit(operation.Type)
			for _, variable := range standardOperationVariables[def.Symbol.ID+"/"+operation.Name] {
				visit(variable)
			}
			for _, requirement := range standardReceiverRequirements[def.Symbol.ID+"/"+operation.Name] {
				visit(requirement.Constraint)
			}
		}
		for _, method := range standardImplementations {
			if method.Receiver.ID == def.Symbol.ID {
				visit(method.Contract)
				visit(method.Type)
			}
		}
	}
	for _, name := range []string{"List", "Map", "Set"} {
		visit(standardSymbols[name].Type)
	}
	got := []string{}
	for name := range names {
		got = append(got, name)
	}
	slices.Sort(got)
	want := []string{"CollectionError", "Equal", "Error", "Hashable", "List", "ListEntry", "Map", "MapEntry", "Optional", "Result", "Set"}
	if !slices.Equal(got, want) {
		t.Fatalf("support closure = %v, want %v", got, want)
	}
	m, err := parser.Parse("prelude.ms", "fn use() -> Unit: unit\n")
	if err != nil {
		t.Fatal(err)
	}
	p := Check([]*syntax.Module{m}, nil)
	for _, name := range got {
		if p.symbols[m.File][name] != standardSymbols[name] {
			t.Errorf("%s lost its canonical declaration identity", name)
		}
	}
}

func TestRedundantPreludeImportDiagnosticsAndFixes(t *testing.T) {
	for _, name := range standardPreludeNames {
		symbol := standardSymbols[name]
		if symbol == nil {
			ensureStandard()
			symbol = standardSymbols[name]
		}
		source := "import " + name + " from \"" + symbol.Module + "\"\nfn use() -> Unit: unit\n"
		t.Run(name, func(t *testing.T) { checkPreludeImportFix(t, source, name, "", true) })
	}
	for _, tc := range []struct{ name, source, keep string }{
		{"first", "import { List, range } from \"@std/collections.ms\"\n", "range"},
		{"last", "import { range, List } from \"@std/collections.ms\"\n", "range"},
		{"middle", "import { range, List, filled } from \"@std/collections.ms\"\n", "filled"},
		{"trailing comma", "import { range, List, } from \"@std/collections.ms\"\n", "range"},
		{"multiline comment", "import {\n    range, # factory\n    List # collection\n} from \"@std/collections.ms\"\n", "# collection"},
		{"comma after comment", "import {\n    List # collection\n    , range\n} from \"@std/collections.ms\"\n", "# collection"},
		{"space before comma", "import {\n    List , range\n} from \"@std/collections.ms\"\n", "range"},
		{"last next to closer", "import {\n    range, # factory\n    List } from \"@std/collections.ms\"\n", "# factory"},
		{"singleton comment", "import List from \"@std/collections.ms\" # keep me\n", "# keep me"},
		{"singleton group comment", "import {\n    # keep me\n    List,\n} from \"@std/collections.ms\" # tail\n", "# keep me"},
		{"no newline", "import List from \"@std/collections.ms\"", ""},
	} {
		for _, newline := range []string{"\n", "\r\n"} {
			t.Run(tc.name+newline, func(t *testing.T) {
				checkPreludeImportFix(t, strings.ReplaceAll(tc.source, "\n", newline), "List", tc.keep, true)
			})
		}
	}
	checkPreludeImportFix(t, "import {List, Map, Set} from \"@std/collections.ms\"\n", "Map", "Set", false)
}

func checkPreludeImportFix(t *testing.T, source, name, keep string, success bool) {
	t.Helper()
	module, err := parser.Parse("imports.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	p := Check([]*syntax.Module{module}, nil)
	var issue *syntax.Diagnostic
	for i := range p.Diagnostics {
		d := &p.Diagnostics[i]
		if d.Message == "redundant prelude import "+name+"; remove "+name+" from this import and use its prelude declaration directly" {
			issue = d
			break
		}
	}
	if issue == nil || issue.Code() != "MS2003" || issue.End == nil || issue.Fix == nil {
		t.Fatal(p.Diagnostics)
	}
	if source[issue.Position.Offset:issue.End.Offset] != name {
		t.Fatal(*issue)
	}
	fix := issue.Fix
	fixed := source[:fix.Position.Offset] + fix.Replacement + source[fix.End.Offset:]
	if keep != "" && !strings.Contains(fixed, keep) {
		t.Fatal(fixed)
	}
	if strings.Contains(source, "\r\n") && strings.Contains(strings.ReplaceAll(fixed, "\r\n", ""), "\n") {
		t.Fatalf("changed line endings: %q", fixed)
	}
	updated, err := parser.Parse("imports.ms", fixed)
	if err != nil {
		t.Fatalf("fix is invalid: %v\n%s", err, fixed)
	}
	after := Check([]*syntax.Module{updated}, nil)
	if success && len(after.Diagnostics) != 0 {
		t.Fatal(after.Diagnostics, fixed)
	}
}

func TestPreludeImportFixSurvivesUnrelatedLexerErrors(t *testing.T) {
	for _, source := range []string{
		"import List from \"@std/collections.ms\"\nfn broken(\n",
		"import {ListBuilder, List} from \"@std/collections.ms\"\nfn broken(\n",
		"import List from \"@std/collections.ms\"\nfn bad() -> String: \"unterminated\n",
		"fn bad() -> Unit:\n   unit\nimport List from \"@std/collections.ms\"\n",
	} {
		for _, newline := range []string{"\n", "\r\n"} {
			source := strings.ReplaceAll(source, "\n", newline)
			module, parseIssues := parser.ParsePartial("recovery.ms", source)
			if len(parseIssues) == 0 {
				t.Fatal("fixture needs a lexer error")
			}
			program := Check([]*syntax.Module{module}, nil)
			found := false
			for _, issue := range program.Diagnostics {
				if issue.Code() != "MS2003" {
					continue
				}
				found = true
				if issue.Fix == nil {
					t.Fatal("lost a valid import fix", issue)
				}
				fix := issue.Fix
				fixed := source[:fix.Position.Offset] + fix.Replacement + source[fix.End.Offset:]
				updated, _ := parser.ParsePartial("recovery.ms", fixed)
				for _, imp := range updated.Imports {
					if imp.Name == "List" {
						t.Fatal("fix retained prelude import", fixed)
					}
				}
				if strings.Contains(source, "ListBuilder") && !strings.Contains(fixed, "ListBuilder") {
					t.Fatal(fixed)
				}
				if strings.Contains(source, "\r\n") && strings.Contains(strings.ReplaceAll(fixed, "\r\n", ""), "\n") {
					t.Fatal("changed line endings", fixed)
				}
			}
			if !found {
				t.Fatal("recovery lost the import", program.Diagnostics)
			}
		}
	}
}
