package tooling

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestPreferredNamesFollowResolvedNativeMethods(t *testing.T) {
	for _, tc := range []struct {
		name, imports, typ, old, preferred, arguments, behavior string
	}{
		{"List set", "", "List[Int]", "with_value", "set", "index: -1, value: 7", "mutates and returns the receiver"},
		{"List remove", "", "List[Int]", "without", "remove", "index: -1", "mutates and returns the receiver"},
		{"List reverse", "", "List[Int]", "reverse", "reverse_in_place", "", "mutates and returns the receiver"},
		{"List splice", "", "List[Int]", "with_values", "splice", "start: 0, delete_count: 0, replacement: [7]", "mutates and returns the receiver"},
		{"Map add", "", "Map[Int, Int]", "with_entry", "add", "key: 1, value: 7", "mutates and returns the receiver"},
		{"Map remove", "", "Map[Int, Int]", "without", "remove", "key: 1", "mutates and returns the receiver"},
		{"Map default", "", "Map[Int, Int]", "with_default", "add_default", "key: 1, value: 7", "mutates and returns the receiver"},
		{"Map lazy default", "", "Map[Int, Int]", "with_default_from", "add_default_from", "key: 1, create: fn(key): key + 7", "mutates and returns the receiver"},
		{"Map builder", "import MapBuilder from \"@std/collections.ms\"\n", "MapBuilder[Int, Int]", "with_entry", "add", "key: 1, value: 7", "mutates the builder and returns Unit"},
		{"Set builder", "import SetBuilder from \"@std/collections.ms\"\n", "SetBuilder[Int]", "with_value", "add", "value: 7", "mutates the builder and returns Unit"},
		{"Set add", "import Set from \"@std/collections.ms\"\n", "Set[Int]", "with_value", "add", "value: 7", "mutates and returns the receiver"},
		{"Set remove", "import Set from \"@std/collections.ms\"\n", "Set[Int]", "without", "remove", "value: 7", "mutates and returns the receiver"},
		{"Bytes reverse", "import Bytes from \"@std/bytes.ms\"\n", "Bytes", "reverse", "reversed", "", "returns a copy"},
		{"Regex replace", "import Regex from \"@std/regex.ms\"\n", "Regex", "replace", "replace_all", "text: \"aaa\", replacement: \"b\"", "replaces all matches"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			for _, bound := range []bool{false, true} {
				use := "    let _result = receiver." + tc.old + "(" + tc.arguments + ")\n"
				if bound {
					use = "    let operation = receiver." + tc.old + "\n    let _result = operation(" + tc.arguments + ")\n"
				}
				source := tc.imports + "fn use(receiver: " + tc.typ + ") -> Unit:\n" + use
				findings := preferredNameFindings(t, "source.ms", source)
				name := strings.Split(tc.typ, "[")[0]
				message := name + "." + tc.old + " " + tc.behavior + "; use " + name + "." + tc.preferred + " with the same arguments"
				if len(findings) != 1 || findings[0].Message != message || findings[0].Position.Offset != strings.Index(source, "receiver."+tc.old)+len("receiver.") {
					t.Fatalf("bound=%v: %+v", bound, findings)
				}
				preferred := strings.Replace(source, "receiver."+tc.old, "receiver."+tc.preferred, 1)
				if findings := preferredNameFindings(t, "source.ms", preferred); len(findings) != 0 {
					t.Fatalf("preferred method warned: %+v", findings)
				}
			}
		})
	}
}

func TestPreferredNamesPreserveUserMethodsFieldsAndCopyContracts(t *testing.T) {
	source := `import {MapBuilder, SetBuilder} from "@std/collections.ms"
import Bytes from "@std/bytes.ms"

interface Legacy:
    fn with_value(value: Int) -> Unit
    fn reverse() -> Unit

type User:
    reverse: fn() -> Unit
    with_entry: fn(key: Int, value: Int) -> Unit

impl Legacy for User:
    fn with_value(value: Int) -> Unit:
        let _ignored = value
    fn reverse() -> Unit:
        self.reverse()

fn generic[T: Legacy](value: T) -> Unit:
    value.with_value(1)

fn use(value: User, bytes: Bytes, map: Map[Int, Int], mb: MapBuilder[Int, Int], sb: SetBuilder[Int]) -> Unit:
    value.with_value(1)
    value.reverse()
    value.with_entry(1, 2)
    Legacy(value).reverse()
    generic(value)
    let _copy = bytes.with_value(index: 0, value: 1)
    let _map = map.remove(key: 1)
    mb.add(key: 1, value: 2)
    sb.add(value: 1)
    let replace = "aaa".replace
    let first = "aaa".replace_first
    let _capped = replace(old: "a", new: "b", max_replacements: 2)
    let _also_capped = first(old: "a", new: "b", max_replacements: 2)
`
	if findings := preferredNameFindings(t, "source.ms", source); len(findings) != 0 {
		t.Fatal(findings)
	}
}

func TestPreferredNamesKeepImportedModulePositions(t *testing.T) {
	root := t.TempDir()
	for name, source := range map[string]string{
		"helper.ms": "export fn mutate(values: List[Int]) -> Unit:\n    values.with_value(index: 0, value: 1)\n",
		"main.ms":   "import mutate from \"./helper.ms\"\nfn use() -> Unit:\n    mutate([0])\n",
	} {
		if err := os.WriteFile(filepath.Join(root, name), []byte(source), 0600); err != nil {
			t.Fatal(err)
		}
	}
	checked := compiler.CompileFile(filepath.Join(root, "main.ms"), compiler.Options{AnalyzeOnly: true})
	if !checked.Success() {
		t.Fatal(checked.Diagnostics)
	}
	var findings []LintFinding
	for _, finding := range LintProgram(checked.Program) {
		if finding.Code == "MSL108" {
			findings = append(findings, finding)
		}
	}
	if len(findings) != 1 || findings[0].Position.File != "helper.ms" || findings[0].Position.Line != 2 || findings[0].Position.Column != 12 {
		t.Fatal(findings)
	}
}

func TestStandardImplementationsUsePreferredNames(t *testing.T) {
	checked := compiler.CompileSource("standard-names.ms", `import YamlValue from "@std/yaml.ms"
import TomlValue from "@std/toml.ms"
fn use(yaml: YamlValue, toml: TomlValue) -> Unit:
    let _yaml = yaml
    let _toml = toml
`, compiler.Options{AnalyzeOnly: true})
	if !checked.Success() {
		t.Fatal(checked.Diagnostics)
	}
	seen := map[string]bool{}
	for expression, info := range checked.Program.Expressions() {
		if !strings.HasPrefix(expression.Pos.File, "@std/") || info == nil || info.Method == nil || info.Method.Receiver == nil || info.Method.Contract != nil {
			continue
		}
		seen[expression.Pos.File] = true
		method := info.Method
		if preferred := preferredNativeMethods[method.Receiver.ID+"/"+method.Native]; preferred != "" {
			t.Errorf("%s: use %s in standard implementation", expression.Pos, preferred)
		}
	}
	for _, module := range []string{"@std/yaml.ms", "@std/toml.ms"} {
		if !seen[module] {
			t.Errorf("standard implementation was not inspected: %s", module)
		}
	}
}

func preferredNameFindings(t *testing.T, filename, source string) []LintFinding {
	t.Helper()
	checked := compiler.CompileSource(filename, source, compiler.Options{AnalyzeOnly: true})
	if !checked.Success() {
		t.Fatal(checked.Diagnostics)
	}
	var findings []LintFinding
	for _, finding := range LintProgram(checked.Program) {
		if finding.Code == "MSL108" {
			findings = append(findings, finding)
		}
	}
	return findings
}
