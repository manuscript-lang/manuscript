package compiler

import "testing"

func TestOptionalMethodsRejectInvalidContracts(t *testing.T) {
	for name, source := range map[string]string{
		"wrong fallback": `import Optional from "@std/optional.ms"
fn wrong(value: Optional[Int]) -> Int:
    return value.unwrap_or("missing")
`,
		"wrong lazy fallback result": `import Optional from "@std/optional.ms"
fn create() -> String: return "missing"
fn wrong(value: Optional[Int]) -> Int:
    return value.unwrap_or_else(create)
`,
		"lazy fallback requires zero parameters": `import Optional from "@std/optional.ms"
fn create(value: Int) -> Int: return value
fn wrong(value: Optional[Int]) -> Int:
    return value.unwrap_or_else(create)
`,
		"nested values do not flatten": `import Optional from "@std/optional.ms"
fn wrong(value: Optional[Optional[Int]]) -> Int:
    return value.unwrap()
`,
		"result does not inherit optional methods": `import Result from "@std/result.ms"
fn wrong(value: Result[Int, String]) -> Int:
    return value.unwrap()
`,
		"local names do not inherit native methods": `type Optional[T]:
    case some(value: T)
    case none
fn wrong(value: Optional[Int]) -> Int:
    return value.unwrap()
`,
		"private implementation is not a second public spelling": `import unwrap from "@std/optional.ms"
`,
	} {
		t.Run(name, func(t *testing.T) {
			if result := CompileSource("optional.ms", source, Options{}); result.Success() {
				t.Fatal("accepted an invalid Optional contract")
			}
		})
	}
}
