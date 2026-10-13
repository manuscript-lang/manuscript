package compiler

import (
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestNativeDefaultCallableBoundaries(t *testing.T) {
	const prefix = `import {base64_encode, base64_decode} from "@std/encoding.ms"
import {parse, CsvOptions} from "@std/csv.ms"
import {commands, Commands, CommandOutput, CommandError} from "@std/process.ms"
import {Bytes} from "@std/bytes.ms"
import List from "@std/collections.ms"
import Duration from "@std/time.ms"
fn forward[T](item: T) -> T: item
`
	for _, item := range []struct{ name, body, want string }{
		{"missing data", "base64_encode()", "missing argument data"},
		{"wrong bool", "base64_encode(Bytes([]), url_safe: none)", "expected Bool"},
		{"wrong options", "parse(\"a\", options: none)", "expected CsvOptions"},
		{"typed callable", "let f: fn(data: Bytes, url_safe: Bool) -> String = base64_encode\n    f(Bytes([]))", "missing argument url_safe"},
		{"mutable callable", "var f = base64_encode\n    f(Bytes([]))", "missing argument url_safe"},
		{"forwarded callable", "let f = forward(base64_encode)\n    f(Bytes([]))", "missing argument url_safe"},
		{"typed bound method", "let f: fn(program: String, arguments: List[String], input: Bytes, max_output_bytes: Optional[Int], timeout: Optional[Duration]) -> Result[CommandOutput, CommandError] = commands().run\n    f(program: \"\", arguments: [])", "missing argument input"},
	} {
		t.Run(item.name, func(t *testing.T) {
			r := CompileSource("boundary.ms", prefix+"fn check() -> Unit:\n    "+item.body+"\n", Options{AnalyzeOnly: true})
			if r.Success() || !strings.Contains(fmt.Sprint(r.Diagnostics), item.want) {
				t.Fatalf("want %s: %v", item.want, r.Diagnostics)
			}
		})
	}
}

// Route ordinarily checked source declarations to the real CSV native ABI in
// this private lowering test. It exercises effectful defaults without changing
// the shipped stdlib or its immutable registry to manufacture side effects.
func TestNativeDefaultsEvaluateBeforeDispatch(t *testing.T) {
	const source = `import {CsvOptions, CsvError} from "@std/csv.ms"
import List from "@std/collections.ms"
import panic from "@std/faults.ms"
fn options(rows: List[List[String]], mark: String) -> CsvOptions:
    rows.append([mark])
    return CsvOptions()
fn supplied(rows: List[List[String]]) -> List[List[String]]:
    rows.append(["2"])
    return rows
fn budget(rows: List[List[String]]) -> Optional[Int]:
    rows.append(["4"])
    return none
fn native(
    rows: List[List[String]], options: CsvOptions = options(rows, "3"),
    max_bytes: Optional[Int] = budget(rows)
) -> Result[String, CsvError]:
    return ok("source stub")
fn failed_options(rows: List[List[String]]) -> Result[CsvOptions, CsvError]:
    rows.append(["failed"])
    return error(CsvError.InvalidInput)
fn failing(
    rows: List[List[String]], options: CsvOptions = try failed_options(rows),
    max_bytes: Optional[Int] = budget(rows)
) -> Result[String, CsvError]:
    return ok("source stub")
test "native preparation order skip repetition and propagation":
    let rows: List[List[String]] = []
    let chosen = options(rows, "1")
    let callable = native
    if callable(rows: supplied(rows), options: chosen) != Result[String, CsvError].ok("1\n2\n4\n"):
        return panic("supplied expressions before remaining defaults")
    let again: List[List[String]] = []
    if callable(again) != Result[String, CsvError].ok("3\n4\n"):
        return panic("defaults run in declaration order")
    let third: List[List[String]] = []
    if callable(third) != Result[String, CsvError].ok("3\n4\n"):
        return panic("fresh evaluation on repeat")
    let explicit: List[List[String]] = []
    if callable(explicit, chosen, none) != Result[String, CsvError].ok("") or explicit.length() != 0:
        return panic("present values skip all defaults including explicit none")
    let options_only: List[List[String]] = []
    if native(options_only, max_bytes: none) != Result[String, CsvError].ok("3\n"):
        return panic("cached callable must retain every default slot")
    let budget_only: List[List[String]] = []
    if native(budget_only, options: chosen) != Result[String, CsvError].ok("4\n"):
        return panic("cached callable must support another omission subset")
    let stopped: List[List[String]] = []
    if failing(stopped) != Result[String, CsvError].error(CsvError.InvalidInput) or stopped != [["failed"]]:
        return panic("default failure stops later defaults and native body")
`
	r := CompileSource("native-defaults.ms", source, Options{Tests: true, AnalyzeOnly: true})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	for _, name := range []string{"native", "failing"} {
		r.Program.Symbols["native-defaults.ms"][name].Native = "csv/stringify"
	}
	generated, err := lowerGo(optimize(r.Program), "native-defaults.ms", Options{Tests: true})
	if err != nil {
		t.Fatal(err)
	}
	binary := filepath.Join(t.TempDir(), "defaults")
	if err := Build(generated, binary); err != nil {
		t.Fatal(err)
	}
	if output, err := exec.Command(binary).CombinedOutput(); err != nil || !strings.Contains(string(output), "1 tests, 0 failed") {
		t.Fatalf("native defaults: %v\n%s", err, output)
	}
}

func TestExplicitNativeCallsKeepDirectDispatch(t *testing.T) {
	r := CompileSource("explicit-native.ms", `import base64_encode from "@std/encoding.ms"
import CsvOptions from "@std/csv.ms"
import {commands} from "@std/process.ms"
import List from "@std/collections.ms"
import Bytes from "@std/bytes.ms"
fn explicit(data: Bytes) -> Unit:
    base64_encode(data,false)
    CsvOptions(",","\n")
    commands().run(program: "",arguments: [],input: data)
`, Options{})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	if strings.Contains(r.Source, "WithDefaults") || strings.Contains(r.Source, "PreparedDefaults") {
		t.Fatal("explicit calls emitted default preparation")
	}
}

func TestRecursiveNativeDefaultExpansionIsRejected(t *testing.T) {
	for _, source := range []string{
		`import Bytes from "@std/bytes.ms"
fn recursive(data: Bytes, url_safe: Bool = recursive(data) == "") -> String: "stub"
fn call() -> String: recursive("".to_bytes())
`,
		`type Recursive:
    value: Int = Recursive().value
fn call() -> Recursive: Recursive()
`,
	} {
		r := CompileSource("recursive-native.ms", source, Options{AnalyzeOnly: true})
		if !r.Success() {
			t.Fatal(r.Diagnostics)
		}
		for _, name := range []string{"recursive", "Recursive"} {
			if symbol := r.Program.Symbols["recursive-native.ms"][name]; symbol != nil {
				symbol.Native = "encoding/base64_encode"
			}
		}
		_, err := lowerGo(optimize(r.Program), "recursive-native.ms", Options{})
		if err == nil || !strings.Contains(err.Error(), "recursive native default expansion") {
			t.Fatalf("recursive native default: %v", err)
		}
	}
}
