package build

import (
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	rt "github.com/manuscript-lang/manuscript/pkg/runtime"
	goparser "go/parser"
	"go/token"
	"os"
	"os/exec"
	"path/filepath"
	goruntime "runtime"
	"strconv"
	"strings"
	"testing"
)

func TestPublicLibraryFunctionsAreImportable(t *testing.T) {
	for _, module := range checker.StandardModuleNames() {
		for name := range checker.StandardExports(module) {
			t.Run(module+"/"+name, func(t *testing.T) {
				source := fmt.Sprintf("import %s from \"%s\"\n", name, module)
				result := compiler.CompileSource("imports.ms", source, compiler.Options{})
				for _, d := range result.Diagnostics {
					if !strings.Contains(d.Message, "redundant prelude import") {
						t.Fatal(result.Diagnostics)
					}
				}
			})
		}
	}
}
func TestOpaqueLibraryTypesCannotBeConstructed(t *testing.T) {
	for _, spec := range []struct{ module, name string }{{"bigint", "BigInt"}, {"regex", "Regex"}, {"time", "Timestamp"}} {
		source := fmt.Sprintf("import %s from \"@std/%s.ms\"\ntest \"reject\":\n    let value = %s()\n", spec.name, spec.module, spec.name)
		if result := compiler.CompileSource("opaque.ms", source, compiler.Options{}); result.Success() {
			t.Fatal("accepted native constructor", spec.name)
		}
	}
}

func TestLibraryErrorDomainsAreDistinct(t *testing.T) {
	prefix := `import JsonError from "@std/json.ms"
import EncodingError from "@std/encoding.ms"
`
	for name, source := range map[string]string{
		"unrelated error": `fn wrong() -> Result[Unit, JsonError]:
    return error(cause: EncodingError.InvalidData)
`,
		"impossible case": `fn wrong() -> JsonError:
    return JsonError.PermissionDenied
`,
		"implicit propagation": `import hex_decode from "@std/encoding.ms"
fn wrong() -> Result[Unit, JsonError]:
    let bytes = try hex_decode(text: "ff", max_bytes: 1)
    return ok(value: unit)
`,
	} {
		t.Run(name, func(t *testing.T) {
			result := compiler.CompileSource("errors.ms", prefix+source, compiler.Options{})
			if result.Success() {
				t.Fatal("accepted incompatible error contract")
			}
		})
	}
}

func TestCommonErrorRejectsInvalidContractPatterns(t *testing.T) {
	prefix := `import JsonError from "@std/json.ms"
import EncodingError from "@std/encoding.ms"
`
	for name, source := range map[string]string{
		"missing implicit implementation": `type Impostor:
    detail: String
fn wrong(value: Impostor) -> Error:
    return value
`,
		"unimplemented try error": `fn failure() -> Result[Unit, String]:
    return error(cause: "diagnostic")
fn wrong() -> Result[Unit, Error]:
    let completed = try failure()
    return ok(value: unit)
`,
		"result success remains exact": `fn wrong() -> Result[String, Error]:
    return Result[Int, JsonError].ok(value: 1)
`,
		"Error cannot narrow to a domain": `fn wrong(value: Error) -> JsonError:
    return value
`,
		"error lists remain invariant": `fn wrong(values: List[JsonError]) -> List[Error]:
    return values
`,
		"error function types remain invariant": `fn wrong(operation: fn() -> JsonError) -> fn() -> Error:
    return operation
`,
		"other implemented interfaces require a view": `interface Diagnostic:
    fn message() -> String
type LocalError:
    detail: String
impl Diagnostic for LocalError:
    fn message() -> String:
        return self.detail
fn wrong(value: LocalError) -> Diagnostic:
    return value
`,
		"missing implementation": `type Impostor:
    detail: String
fn wrong(value: Impostor) -> Error:
    return Error(value: value)
`,
		"open contract needs fallback": `fn wrong(cause: Error) -> String:
    match cause:
        JsonError(value):
            return value.message()
`,
		"case is not a type": `fn wrong(cause: Error) -> String:
    match cause:
        JsonError.InvalidData(value):
            return "invalid"
        _:
            return cause.message()
`,
		"payload arity": `fn wrong(cause: Error) -> String:
    match cause:
        JsonError:
            return "invalid"
        _:
            return cause.message()
`,
		"unrelated concrete type": `type Other:
    detail: String
fn wrong(cause: Error) -> String:
    match cause:
        Other(value):
            return value.detail
        _:
            return cause.message()
`,
		"duplicate type": `fn wrong(cause: Error) -> String:
    match cause:
        JsonError(first):
            return first.message()
        JsonError(second):
            return second.message()
        _:
            return cause.message()
`,
		"fallback must be last": `fn wrong(cause: Error) -> String:
    match cause:
        _:
            return cause.message()
        JsonError(value):
            return value.message()
`,
		"unbound generic type": `type Box[T]:
    item: T
impl Error for Box[T]:
    fn message() -> String:
        return "box"
fn wrong(cause: Error) -> String:
    match cause:
        Box(value):
            return value.message()
        _:
            return cause.message()
`,
	} {
		t.Run(name, func(t *testing.T) {
			result := compiler.CompileSource("common-errors.ms", prefix+source, compiler.Options{})
			if result.Success() {
				t.Fatal("accepted invalid common error or pattern")
			}
		})
	}
}

func TestCommonErrorAcceptsSpecificErrors(t *testing.T) {
	source := `import JsonError from "@std/json.ms"
import hex_decode from "@std/encoding.ms"
fn general(cause: JsonError) -> Error:
    return cause
fn failed() -> Result[Unit, JsonError]:
    return error(cause: JsonError.InvalidData)
fn forwarded() -> Result[Unit, Error]:
    return failed()
fn propagated() -> Result[Unit, Error]:
    let bytes = try hex_decode(text: "zz")
    return ok(value: unit)
fn constructed() -> Result[Unit, Error]:
    return error(cause: JsonError.InvalidData)
`
	result := compiler.CompileSource("direct-errors.ms", source, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	if strings.Contains(result.Source, "rt.ViewOf(") {
		t.Fatal("ordinary specific errors gained a runtime view wrapper")
	}
}

func TestAllStandardErrorsImplementError(t *testing.T) {
	for _, module := range checker.StandardLibrary() {
		if module.Path == "prelude" {
			continue // Prelude aliases retain their defining module's identity.
		}
		for _, declaration := range module.Declarations {
			if declaration.Kind != "alternative" || !strings.HasSuffix(declaration.Name, "Error") {
				continue
			}
			t.Run(declaration.Name, func(t *testing.T) {
				source := fmt.Sprintf(`fn diagnostic(cause: %s) -> String:
    return cause.message()
fn view(cause: %s) -> Error:
    return cause
`, declaration.Name, declaration.Name)
				if !checker.IsPreludeSymbol(checker.StandardExports(module.Path)[declaration.Name]) {
					source = fmt.Sprintf("import %s from %q\n", declaration.Name, module.Path) + source
				}
				result := compiler.CompileSource("standard-errors.ms", source, compiler.Options{})
				if !result.Success() {
					t.Fatal(result.Diagnostics)
				}
				if len(declaration.Implements) != 1 || declaration.Implements[0] != "Error" {
					t.Fatalf("missing implementation in documentation: %+v", declaration)
				}
			})
		}
	}
}

// Standalone folds runtime files into one Go file and deduplicates imports by
// path. Different aliases for the same import would pass package tests but fail
// every emitted program; catch that drift before invoking the native compiler.
func TestBundledRuntimeImportAliasesAgree(t *testing.T) {
	entries, err := rt.Sources.ReadDir(".")
	if err != nil {
		t.Fatal(err)
	}
	aliases := map[string]string{}
	for _, entry := range entries {
		data, err := rt.Sources.ReadFile(entry.Name())
		if err != nil {
			t.Fatal(err)
		}
		file, err := goparser.ParseFile(token.NewFileSet(), entry.Name(), data, goparser.ImportsOnly)
		if err != nil {
			t.Fatal(err)
		}
		for _, spec := range file.Imports {
			path, err := strconv.Unquote(spec.Path.Value)
			if err != nil {
				t.Fatal(err)
			}
			alias := filepath.Base(path)
			if spec.Name != nil {
				alias = spec.Name.Name
			}
			if prior, ok := aliases[path]; ok && prior != alias {
				t.Errorf("%s imports %s as %s; bundled runtime also uses %s", entry.Name(), path, alias, prior)
			}
			aliases[path] = alias
		}
	}
}

func TestTimeSchedulingAcceptsOrdinaryCallbackValues(t *testing.T) {
	source := `import Scheduler from "@std/tasks.ms"
fn start_timer(operation: fn() -> Result[Unit, Error]) -> Unit:
    with scheduler = Scheduler():
        let schedule = scheduler.after
        let id = schedule(duration: 0.milliseconds, operation: operation)
`
	if result := compiler.CompileSource("timer-values.ms", source, compiler.Options{}); !result.Success() {
		t.Fatal(result.Diagnostics)
	}
}

func TestNativeBuildInSymlinkedTemporaryDirectory(t *testing.T) {
	root := t.TempDir()
	actual, alias := filepath.Join(root, "actual"), filepath.Join(root, "alias")
	if err := os.Mkdir(actual, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(actual, alias); err != nil {
		t.Skipf("symlink unavailable: %v", err)
	}
	for _, name := range []string{"TMPDIR", "TMP", "TEMP"} {
		t.Setenv(name, alias)
	}
	// The shared native workspace lives in the cache root.
	t.Setenv("MANUSCRIPT_CACHE_DIR", alias)
	result := compiler.CompileSource("native-path.ms", `test "native module identity":
    let value = 1
`, compiler.Options{Tests: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	binary := filepath.Join(root, "program")
	if goruntime.GOOS == "windows" {
		binary += ".exe"
	}
	if err := Build(result.Source, binary); err != nil {
		t.Fatal(err)
	}
	output, err := exec.Command(binary).CombinedOutput()
	if err != nil || !strings.Contains(string(output), "0 failed") {
		t.Fatal(err, string(output))
	}
}
