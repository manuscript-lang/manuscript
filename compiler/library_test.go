package compiler

import (
	"fmt"
	"github.com/manuscript-lang/manuscript/checker"
	rt "github.com/manuscript-lang/manuscript/runtime"
	"strings"
	"testing"
)

func TestAllLibraryFunctionsAreImportable(t *testing.T) {
	for _, spec := range rt.Library {
		t.Run(spec.Module+"/"+spec.Name, func(t *testing.T) {
			source := fmt.Sprintf("import %s from \"@std/%s.ms\"\n", spec.Name, spec.Module)
			result := CompileSource("imports.ms", source, Options{})
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
		})
	}
}
func TestOpaqueLibraryTypesCannotBeConstructed(t *testing.T) {
	for _, spec := range []struct{ module, name string }{{"bigint", "BigInt"}, {"regex", "Regex"}, {"time", "Timestamp"}} {
		source := fmt.Sprintf("import %s from \"@std/%s.ms\"\ntest \"reject\":\n    let value = %s()\n", spec.name, spec.module, spec.name)
		if result := CompileSource("opaque.ms", source, Options{}); result.Success() {
			t.Fatal("accepted native constructor", spec.name)
		}
	}
}

func TestLibraryErrorDomainsAreDistinct(t *testing.T) {
	prefix := `import Result from "@std/result.ms"
import JsonError from "@std/json.ms"
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
			result := CompileSource("errors.ms", prefix+source, Options{})
			if result.Success() {
				t.Fatal("accepted incompatible error contract")
			}
		})
	}
}

func TestCommonErrorRejectsInvalidContractPatterns(t *testing.T) {
	prefix := `import Error from "@std/errors.ms"
import JsonError from "@std/json.ms"
import EncodingError from "@std/encoding.ms"
import Result from "@std/result.ms"
`
	for name, source := range map[string]string{
		"implicit conversion": `fn wrong() -> Error:
    return JsonError.InvalidData
`,
		"implicit try conversion": `import hex_decode from "@std/encoding.ms"
fn wrong() -> Result[Unit, Error]:
    let bytes = try hex_decode(text: "ff", max_bytes: 1)
    return ok(value: unit)
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
			result := CompileSource("common-errors.ms", prefix+source, Options{})
			if result.Success() {
				t.Fatal("accepted invalid common error or pattern")
			}
		})
	}
}

func TestAllStandardErrorsImplementError(t *testing.T) {
	for _, module := range checker.StandardLibrary() {
		for _, declaration := range module.Declarations {
			if declaration.Kind != "alternative" || !strings.HasSuffix(declaration.Name, "Error") {
				continue
			}
			t.Run(declaration.Name, func(t *testing.T) {
				source := fmt.Sprintf(`import Error from "@std/errors.ms"
import %s from %q
fn diagnostic(cause: %s) -> String:
    return Error(value: cause).message()
fn view(cause: %s) -> Error:
    return Error(value: cause)
`, declaration.Name, module.Path, declaration.Name, declaration.Name)
				result := CompileSource("standard-errors.ms", source, Options{})
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
