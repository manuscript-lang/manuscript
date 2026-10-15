package checker

import (
	"slices"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func checkAccessorSource(t *testing.T, source string) (*Program, *syntax.Module) {
	t.Helper()
	module, err := parser.Parse("accessors.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	return Check([]*syntax.Module{module}, nil), module
}

const sourceAccessorFixture = `interface Sized:
    get length -> Int
type Buffer[T]:
    items: List[T]
impl Sized for Buffer[T]:
    get length -> Int:
        return self.items.length
fn concrete(value: Buffer[Int]) -> Int: return value.length
fn viewed(value: Buffer[Int]) -> Int: return Sized(value).length
fn bounded[T: Sized](value: T) -> Int: return value.length
`

func TestAccessorCheckedIdentityAcrossMemberPaths(t *testing.T) {
	program, module := checkAccessorSource(t, sourceAccessorFixture)
	if len(program.Diagnostics) != 0 {
		t.Fatal(program.Diagnostics)
	}
	contract := program.Symbol(module.File, "Sized").Type
	operation := contract.Def.Operations[0]
	if !operation.Accessor || operation.Decl != module.Declarations[0].Methods[0] || operation.Type.Kind != "function" || operation.Type.Result.ID != "Int" {
		t.Fatalf("accessor contract lost declaration/category: %#v", operation)
	}
	for _, name := range []string{"concrete", "viewed", "bounded"} {
		var declaration *syntax.Declaration
		for _, candidate := range module.Declarations {
			if candidate.Name == name {
				declaration = candidate
			}
		}
		info := program.Info(declaration.Body[0].Value)
		if info == nil || info.Type.ID != "Int" || info.Method == nil || !info.Method.Accessor || info.Method.Type.Kind != "function" || info.Method.Type.Result.ID != "Int" {
			t.Fatalf("%s read did not project the selected accessor: %#v", name, info)
		}
		if name != "concrete" && info.Method.Decl != operation.Decl {
			t.Fatalf("%s lost interface operation declaration identity", name)
		}
	}
}

func TestAccessorsRejectMethodConformanceAndAssignment(t *testing.T) {
	for _, test := range []struct{ name, source, want string }{
		{"method for accessor", "interface I:\n    get size -> Int\ntype Box:\n    value: Int\nimpl I for Box:\n    fn size() -> Int: return self.value\n", "must be declared as get size -> Int"},
		{"accessor for method", "interface I:\n    fn size() -> Int\ntype Box:\n    value: Int\nimpl I for Box:\n    get size -> Int: return self.value\n", "must be declared as fn size() -> Int"},
		{"stored field collision", "interface I:\n    get value -> Int\ntype Box:\n    value: Int\nimpl I for Box:\n    get value -> Int: return 1\n", "conflicts with a stored field"},
		{"duplicate kind", "interface I:\n    get value -> Int\n    fn value() -> Int\n", "duplicate operation value"},
		{"native", "fn f(xs: List[Int]) -> Unit:\n    xs.length = 1\n", "cannot assign to read-only accessor length"},
		{"source", sourceAccessorFixture + "fn f(value: Buffer[Int]) -> Unit:\n    value.length = 1\n", "cannot assign to read-only accessor length"},
		{"interface", "interface I:\n    get size -> Int\nfn f(value: I) -> Unit:\n    value.size = 1\n", "cannot assign to read-only accessor size"},
		{"generic", "interface I:\n    get size -> Int\nfn f[T: I](value: T) -> Unit:\n    value.size = 1\n", "cannot assign to read-only accessor size"},
		{"guard", "import SynchronizedGuard from \"@std/sync.ms\"\nfn f(guard: SynchronizedGuard[Int]) -> Unit:\n    guard.value = 1\n", "use guard.set(value: ...)"},
		{"no callable binding", "fn f(xs: List[Int]) -> Unit:\n    let old: fn() -> Int = xs.length\n", "use an explicit closure"},
		{"ambiguity", "interface A:\n    get size -> Int\ninterface B:\n    get size -> Int\ntype Box:\n    value: Int\nimpl A for Box:\n    get size -> Int: return self.value\nimpl B for Box:\n    get size -> Int: return self.value\nfn f(value: Box) -> Int: return value.size\n", "unknown or ambiguous member size"},
	} {
		t.Run(test.name, func(t *testing.T) {
			program, _ := checkAccessorSource(t, test.source)
			found := false
			for _, diagnostic := range program.Diagnostics {
				found = found || strings.Contains(diagnostic.Message, test.want)
			}
			if !found {
				t.Fatalf("expected %q, got %v", test.want, program.Diagnostics)
			}
		})
	}
}

func TestFunctionValuedAccessorCallsValue(t *testing.T) {
	program, module := checkAccessorSource(t, `interface Action:
    get operation -> fn(value: Int) -> Int
type Box:
    offset: Int
impl Action for Box:
    get operation -> fn(value: Int) -> Int:
        return fn(value: Int) -> Int: self.offset + value
fn f(box: Box) -> Int: return box.operation(3)
`)
	if len(program.Diagnostics) != 0 {
		t.Fatal(program.Diagnostics)
	}
	call := module.Declarations[3].Body[0].Value
	if info := program.Info(call.Left); info.Method == nil || !info.Method.Accessor || info.Type.Kind != "function" {
		t.Fatal("function read lost accessor identity", info)
	}
	if info := program.Info(call); info.Type.ID != "Int" || info.Method != nil || info.Native != "" {
		t.Fatal("callback invocation was mistaken for accessor invocation", info)
	}
}

func TestAccessorOldCallsHaveSafeSuffixFixes(t *testing.T) {
	for _, test := range []struct {
		source, want string
		fix          bool
	}{
		{"fn f(xs: List[Int]) -> Int: return xs.length()\n", "xs.length without ()", true},
		{"fn make() -> List[Int]: return [1]\nfn f() -> Int: return make().length()\n", "make().length without ()", true},
		{"fn f() -> Int: return ([1]).length()\n", "([1]).length without ()", true},
		{"fn f(xs: List[Int]) -> Int: return xs.length(1)\n", "xs.length without ()", false},
		{"fn f(xs: List[Int]) -> Int:\n    return xs.length( # keep this comment\n    )\n", "xs.length without ()", false},
		{"import Duration from \"@std/time.ms\"\nfn f(span: Duration) -> Float: return span.to_seconds()\n", "write span.seconds", true},
		{"import SynchronizedGuard from \"@std/sync.ms\"\nfn f(guard: SynchronizedGuard[Int]) -> Int: return guard.get()\n", "write guard.value", true},
	} {
		program, _ := checkAccessorSource(t, test.source)
		var diagnostic *syntax.Diagnostic
		for index := range program.Diagnostics {
			if strings.Contains(program.Diagnostics[index].Message, test.want) {
				diagnostic = &program.Diagnostics[index]
			}
		}
		if diagnostic == nil || (diagnostic.Fix != nil) != test.fix {
			t.Fatalf("want %q, safe fix=%t; got %v", test.want, test.fix, program.Diagnostics)
		}
		if diagnostic.Fix == nil {
			continue
		}
		fix := diagnostic.Fix
		fixed := test.source[:fix.Position.Offset] + fix.Replacement + test.source[fix.End.Offset:]
		checked, _ := checkAccessorSource(t, fixed)
		if len(checked.Diagnostics) != 0 {
			t.Fatalf("fix did not produce valid source: %s\n%v", fixed, checked.Diagnostics)
		}
	}
}

func TestAccessorReadsPropagateEffects(t *testing.T) {
	program, module := checkAccessorSource(t, `interface CounterRead:
    get next -> Int
type Counter:
    values: List[Int]
impl CounterRead for Counter:
    get next -> Int:
        self.values.append(1)
        return self.values.length
fn read(value: Counter) -> Int: return value.next
fn bound(value: Counter) -> fn() -> Int: return fn() -> Int: value.next
fn unresolved(value: CounterRead) -> Int: return value.next
fn native(value: Optional[Int]) -> Bool: return value.is_some
`)
	if len(program.Diagnostics) != 0 {
		t.Fatal(program.Diagnostics)
	}
	for _, name := range []string{"read", "bound"} {
		effects := program.Effects[program.Symbol(module.File, name).ID]
		if !slices.Contains(effects, "read") || !slices.Contains(effects, "write") {
			t.Fatalf("%s dropped accessor body effects: %v", name, effects)
		}
	}
	if effects := program.Effects[program.Symbol(module.File, "unresolved").ID]; !slices.Contains(effects, "unknown") {
		t.Fatal("interface accessor lost unknown implementation effects", effects)
	}
	if effects := program.Effects[program.Symbol(module.File, "native").ID]; !slices.Contains(effects, "read") {
		t.Fatal("native accessor not classified as read", effects)
	}
}

func TestErrorMessageRemainsMethodEverywhere(t *testing.T) {
	ensureStandardSources()
	errorContract := standardSymbols["Error"].Type
	for _, operation := range errorContract.Def.Operations {
		if operation.Name == "message" && (operation.Accessor || operation.Decl.Accessor) {
			t.Fatal("Error.message contract became an accessor")
		}
	}
	implementations := 0
	for _, module := range standardSources {
		for _, declaration := range module.Declarations {
			if declaration.Kind != syntax.KindImpl || declaration.Contract.Name != "Error" {
				continue
			}
			for _, method := range declaration.Methods {
				if method.Name == "message" {
					implementations++
					if method.Accessor {
						t.Fatalf("%s became an accessor", method.Pos)
					}
				}
			}
		}
	}
	if implementations == 0 {
		t.Fatal("standard Error implementations were not discovered")
	}
	program, module := checkAccessorSource(t, `type Failure:
    reason: String
impl Error for Failure:
    fn message() -> String: return self.reason
fn concrete(value: Failure) -> String: return value.message()
fn view(value: Failure) -> String: return Error(value).message()
fn bounded[T: Error](value: T) -> String: return value.message()
fn reference(value: Failure) -> fn() -> String: return value.message
`)
	if len(program.Diagnostics) != 0 {
		t.Fatal(program.Diagnostics)
	}
	last := module.Declarations[len(module.Declarations)-1].Body[0].Value
	if info := program.Info(last); info.Method == nil || info.Method.Accessor || info.Type.Kind != "function" || info.Type.Result.ID != "String" {
		t.Fatal("Error.message no longer binds a callable", info)
	}
}

func TestIntUnitPropertiesUseOrdinaryAccessorIdentity(t *testing.T) {
	program, module := checkAccessorSource(t, `import Duration from "@std/time.ms"
fn f() -> Duration:
    let short = 1.milliseconds
    let medium = 1.seconds
    return 1.minutes
`)
	if len(program.Diagnostics) != 0 {
		t.Fatal(program.Diagnostics)
	}
	reads := 0
	for expression, info := range program.Expressions() {
		if expression.Kind != syntax.KindMember || expression.Pos.File != module.File {
			continue
		}
		reads++
		if info.Method == nil || !info.Method.Accessor || !std(info.Type, "Duration") || info.Method.Decl == nil || !info.Method.Decl.Accessor {
			t.Fatal("Int unit property bypassed declared accessor identity", info)
		}
	}
	if reads != 3 {
		t.Fatal("expected all existing Int units", reads)
	}
}

func TestAccessorLocalImplementationVisibilityAndSubstitution(t *testing.T) {
	base, err := parser.Parse("base.ms", `export type Box[T]:
    stored: T
export interface Reading[T]:
    get value -> T
`)
	if err != nil {
		t.Fatal(err)
	}
	local, err := parser.Parse("local.ms", `import {Box, Reading} from "./base.ms"
impl Reading[T] for Box[T]:
    get value -> T: return self.stored
fn concrete(value: Box[Int]) -> Int: return value.value
fn viewed[T](value: Box[T]) -> T: return Reading[T](value).value
`)
	if err != nil {
		t.Fatal(err)
	}
	imports := map[*syntax.Import]string{}
	for _, item := range local.Imports {
		imports[item] = base.File
	}
	program := Check([]*syntax.Module{base, local}, imports)
	if len(program.Diagnostics) != 0 {
		t.Fatal(program.Diagnostics)
	}
	concrete := program.Info(local.Declarations[1].Body[0].Value)
	if concrete.Method == nil || !concrete.Method.Accessor || !concrete.Method.Local || concrete.Method.Module != local.File || concrete.Type.ID != "Int" {
		t.Fatal("local accessor implementation evidence was lost", concrete)
	}
	viewed := program.Info(local.Declarations[2].Body[0].Value)
	if viewed.Method == nil || !viewed.Method.Accessor || viewed.Type.Kind != "variable" || viewed.Method.Type.Result.ID != viewed.Type.ID {
		t.Fatal("generic interface accessor result was not substituted", viewed)
	}
	outside, err := parser.Parse("outside.ms", "import Box from \"./base.ms\"\nfn f(value: Box[Int]) -> Int: return value.value\n")
	if err != nil {
		t.Fatal(err)
	}
	imports[outside.Imports[0]] = base.File
	program = Check([]*syntax.Module{base, local, outside}, imports)
	if len(program.Diagnostics) != 1 || program.Diagnostics[0].Position.File != outside.File || !strings.Contains(program.Diagnostics[0].Message, "unknown or ambiguous member value") {
		t.Fatal("module-local accessor leaked to an importing module", program.Diagnostics)
	}
}

func TestAccessorPublicResultAndCleanupKinds(t *testing.T) {
	for _, test := range []struct{ source, want string }{
		{"type Hidden:\n    stored: Int\nexport interface Public:\n    get hidden -> Hidden\n", "public signature exposes private type Hidden"},
		{"interface Closer:\n    get close -> Unit\nfn f(value: Closer) -> Unit:\n    with resource = value:\n        return unit\n", "with needs a Closeable value"},
	} {
		program, _ := checkAccessorSource(t, test.source)
		found := false
		for _, diagnostic := range program.Diagnostics {
			found = found || strings.Contains(diagnostic.Message, test.want)
		}
		if !found {
			t.Fatalf("want %q; got %v", test.want, program.Diagnostics)
		}
	}
}
