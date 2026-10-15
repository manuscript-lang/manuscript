package build

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func executeAccessorProgram(t *testing.T, result compiler.Result) {
	t.Helper()
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	binary := filepath.Join(t.TempDir(), "accessors")
	if err := Build(result.Source, binary); err != nil {
		t.Fatal(err)
	}
	output, err := exec.Command(binary).CombinedOutput()
	if err != nil || !strings.Contains(string(output), "0 failed") {
		t.Fatalf("accessor execution: %v\n%s", err, output)
	}
}

func TestAccessorsNativeLiveReadsOrderingAliasesAndMethods(t *testing.T) {
	const source = `import panic from "@std/faults.ms"
import Bytes from "@std/bytes.ms"
import {ClientResponse, HttpResponseMetadata, headers} from "@std/http.ms"
import {duration, timestamp} from "@std/time.ms"
import FileSystemError from "@std/fs.ms"
interface Read:
    get value -> Int
interface Callback:
    get operation -> fn() -> Int
type Box:
    reads: Int
    values: List[Int]
impl Read for Box:
    get value -> Int:
        self.reads = self.reads + 1
        return self.values.length
impl Callback for Box:
    get operation -> fn() -> Int: fn() -> Int: self.values.length
type Cause:
    text: String
    reads: Int
impl Error for Cause:
    fn message() -> String:
        self.reads = self.reads + 1
        return self.text
fn describe[T: Error](value: T) -> String: value.message()
fn read[T: Read](value: T) -> Int: value.value
fn make(box: Box) -> Box:
    box.reads = box.reads + 1
    return box
fn fail() -> Result[Int, String]: error("failed")
fn consume(first: Int, second: Int) -> Int: first + second
fn ordered(box: Box) -> Result[Int, String]: ok(consume(box.value, try fail()))
fn optional(n: Int) -> Optional[Int]: some(n)
fn outcome(n: Int) -> Result[Int, String]: ok(n)
test "receiver once and every read is live":
    let box = Box(0, [])
    if make(box).value != 0 or box.reads != 2: return panic("receiver evaluated incorrectly")
    box.values.append(7)
    if box.value != 1 or box.reads != 3: return panic("read cached")
    let view = Read(box)
    if view.value != 1 or read(box) != 1 or box.reads != 5: return panic("view/generic read missed effects")
    if not ordered(box).is_error or box.reads != 6: return panic("try overtook accessor")
    if box.operation() != 1: return panic("function-valued getter was not invoked")
    let receiver = box.values
    let later: fn() -> Int = fn() -> Int: receiver.length
    box.values.append(8)
    if later() != 2: return panic("closure lost receiver alias")
test "Optional flags keep presence and mutable values":
    let empty: List[List[Int]] = []
    if not empty.first.is_none or not empty.last.is_none: return panic("empty endpoints")
    let nested = List[Optional[Int]]()
    nested.append(none)
    if not nested.first.is_some or not nested.first.unwrap().is_none: return panic("nested none flattened")
    let values = [[1]]
    values.first.unwrap().append(2)
    if values.last.unwrap().length != 2: return panic("endpoint copied mutable element")
    let option = optional(0)
    let result = outcome(0)
    if not option.is_some or option.is_none or not result.is_ok or result.is_error: return panic("typed flags")
test "metadata is a live alias of the current head":
    let first = HttpResponseMetadata(200, headers())
    let response = ClientResponse(first, Bytes([]))
    let saved = response.metadata
    response.metadata.status = 201
    if first.status != 201: return panic("metadata copied")
    let replacement = HttpResponseMetadata(202, headers())
    response.head = replacement
    response.metadata.status = 203
    if saved.status != 201 or replacement.status != 203: return panic("metadata did not follow head")
test "unit projections preserve truncation and precision":
    let span = duration(-1500001)
    if span.nanoseconds != -1500001 or span.microseconds != -1500 or span.milliseconds != -1: return panic("integer unit projection")
    if span.seconds != -0.001500001 or span.minutes != -1500001.0 / 60000000000.0 or span.hours != -1500001.0 / 3600000000000.0: return panic("fractional units")
    if 2.seconds.nanoseconds != 2000000000 or 3.milliseconds.nanoseconds != 3000000 or 1.minutes.seconds != 60.0: return panic("Int units")
    let instant = timestamp(123, 456).unwrap()
    if instant.unix_seconds != 123 or instant.nanoseconds != 456: return panic("timestamp projection")
test "Error.message remains a callable method":
    let cause = Cause("message preserved", 0)
    let bound: fn() -> String = cause.message
    let view = Error(cause)
    let through_view: fn() -> String = view.message
    if cause.reads != 0: return panic("method reference executed message")
    if bound() != "message preserved" or through_view() != "message preserved" or describe(cause) != "message preserved": return panic("Error.message migration")
    if cause.reads != 3: return panic("message execution count")
    let native = FileSystemError.Failed("host text stays verbatim")
    let native_bound: fn() -> String = native.message
    if native_bound() != "host text stays verbatim" or describe(native) != "host text stays verbatim": return panic("native Error.message text changed")
interface Payload[T]:
    get payload -> T
interface Attempt:
    get result -> Result[Int, String]
type Holder[T]:
    stored: T
impl Payload[T] for Holder[T]:
    get payload -> T: self.stored
impl Attempt for Holder[T]:
    get result -> Result[Int, String]:
        let n = try fail()
        return ok(n)
fn payload[T](value: Payload[T]) -> T: value.payload
test "source generic accessor result and propagation":
    let holder = Holder([1])
    let view = Payload[List[Int]](holder)
    payload(view).append(2)
    if holder.payload.length != 2 or view.payload.length != 2: return panic("generic result lost alias/type substitution")
    if not holder.result.is_error: return panic("getter propagation escaped its Result")
`
	executeAccessorProgram(t, compiler.CompileSource("native-accessors.ms", source, compiler.Options{Tests: true}))
}

func TestAccessorReadsPreserveModuleLocalImplementationScopes(t *testing.T) {
	root := t.TempDir()
	sources := map[string]string{
		"domain.ms": `export interface Read:
    get value -> Int
export type Box[T]:
    item: T
`,
		"helper.ms": `import Read from "./domain.ms"
export fn through[T: Read](value: T) -> Int: value.value
export fn use(value: Read) -> Int: value.value
`,
		"main.ms": `import {first, first_generic} from "./first.ms"
import {second, second_generic} from "./second.ms"
import use from "./helper.ms"
import panic from "@std/faults.ms"
test "local accessor implementation evidence survives views and generic arguments":
    if use(first()) != 11 or use(second()) != 22: return panic("view scope lost")
    if first_generic() != 11 or second_generic() != 22: return panic("generic scope lost")
`,
	}
	for name, value := range map[string]string{"first": "11", "second": "22"} {
		sources[name+".ms"] = `import {Box, Read} from "./domain.ms"
import through from "./helper.ms"
impl Read for Box[T]:
    get value -> Int: ` + value + `
export fn ` + name + `() -> Read: Read(Box(7))
export fn ` + name + `_generic() -> Int: through(Box(7))
`
	}
	for name, source := range sources {
		if err := os.WriteFile(filepath.Join(root, name), []byte(source), 0600); err != nil {
			t.Fatal(err)
		}
	}
	executeAccessorProgram(t, compiler.CompileFile(filepath.Join(root, "main.ms"), compiler.Options{Tests: true}))
}

func TestSourceImplementationOfStandardAccessorContract(t *testing.T) {
	const source = `import {Directory, DirectoryEntry, FileSystemError} from "@std/fs.ms"
import {ResponseBody, HttpResponseMetadata, headers} from "@std/http.ms"
import Bytes from "@std/bytes.ms"
import IoError from "@std/io.ms"
import panic from "@std/faults.ms"
type FakeDirectory[T]:
    label: String
    item: T
impl Directory for FakeDirectory[T]:
    get path -> String: self.label
    fn close() -> Unit: unit
    fn read() -> Result[Optional[DirectoryEntry], FileSystemError]: ok(none)
type FakeBody:
    head: HttpResponseMetadata
impl ResponseBody for FakeBody:
    get metadata -> HttpResponseMetadata: self.head
    fn close() -> Unit: unit
    fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]: ok(none)
fn directory[T: Directory](value: T) -> String: value.path
fn body[T: ResponseBody](value: T) -> Int: value.metadata.status
fn view(value: Directory) -> String: value.path
test "standard interface accessors preserve source implementations":
    let source = FakeDirectory("source directory", 7)
    let dynamic = Directory(source)
    if source.path != "source directory" or dynamic.path != "source directory" or directory(source) != "source directory" or view(dynamic) != "source directory": return panic("native directory assertion bypassed implementation")
    source.label = "changed"
    if dynamic.path != "changed": return panic("source path cached")
    let fake = FakeBody(HttpResponseMetadata(207, headers()))
    let response = ResponseBody(fake)
    if fake.metadata.status != 207 or body(fake) != 207 or response.metadata.status != 207: return panic("native body assertion bypassed implementation")
    response.metadata.status = 208
    if fake.head.status != 208: return panic("source metadata alias copied")
`
	executeAccessorProgram(t, compiler.CompileSource("source-standard-accessors.ms", source, compiler.Options{Tests: true}))
}

func TestAccessorFaultFramesAndRecursiveCancellation(t *testing.T) {
	const source = `interface Read:
    get value -> Int
type Plain:
    item: Int
impl Read for Plain:
    get value -> Int: 1 / 0
fn direct() -> Int: Plain(0).value
type Generic[T]:
    item: T
impl Read for Generic[T]:
    get value -> Int: 1 / 0
fn dynamic() -> Int: Generic(0).value
type Loop:
    item: Int
impl Read for Loop:
    get value -> Int: self.value
fn recursive() -> Int: Loop(0).value
type DefaultLoop:
    remaining: Int
impl Read for DefaultLoop:
    get value -> Int:
        if self.remaining <= 0: return 0
        self.remaining = self.remaining - 1
        return defaultRecurse(self)
fn defaultRecurse(loop: DefaultLoop, value: Int = loop.value) -> Int: value
fn defaultRecursive() -> Int: defaultRecurse(DefaultLoop(210000))
`
	result := compiler.CompileSource("fault-accessors.ms", source, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	harness := strings.NewReplacer(
		"@@direct@@", result.Program.Symbol("fault-accessors.ms", "direct").ID,
		"@@dynamic@@", result.Program.Symbol("fault-accessors.ms", "dynamic").ID,
		"@@recursive@@", result.Program.Symbol("fault-accessors.ms", "recursive").ID,
		"@@defaultRecursive@@", result.Program.Symbol("fault-accessors.ms", "defaultRecursive").ID,
	).Replace(`
func accessorFailure(body func()) (failure any) {defer func(){failure=recover()}();body();return}
func checkAccessorFaults() {
 for _,entry:=range []struct{function rt.Value; name string}{{@@direct@@,"Plain.value"},{@@dynamic@@,"Generic.value"}} {
  ctx:=rt.RootExecution()
  failure:=accessorFailure(func(){entry.function.(rt.Function).Body(ctx,nil)})
  rt.FinishExecution(ctx)
  fault,ok:=failure.(rt.Fault)
  if !ok || !strings.Contains(fault.Message,"zero") {panic(fmt.Sprintf("accessor fault changed: %#v",failure))}
  found:=false
  for _,frame:=range fault.Frames {found=found || strings.Contains(frame,"fault-accessors.ms:") && strings.HasSuffix(frame," in "+entry.name)}
  if !found {panic(fmt.Sprintf("accessor source frame lost for %s: %#v",entry.name,fault))}
 }
 for _,entry:=range []rt.Value{@@recursive@@,@@defaultRecursive@@} {
  ctx:=rt.RootExecution()
  failure:=accessorFailure(func(){entry.(rt.Function).Body(ctx,nil)})
  rt.FinishExecution(ctx)
  fault,ok:=failure.(rt.Fault)
  if !ok || !strings.Contains(fault.Message,"call depth limit") {panic(fmt.Sprintf("accessor depth check lost: %#v",failure))}
  cancelled:=rt.RootExecution()
  var cancel context.CancelFunc
  cancelled.Context,cancel=context.WithCancel(cancelled.Context);cancel()
  expected:=accessorFailure(func(){rt.CheckCancelled(cancelled)})
  failure=accessorFailure(func(){entry.(rt.Function).Body(cancelled,nil)})
  rt.FinishExecution(cancelled)
  if failure==nil || !reflect.DeepEqual(failure,expected) {panic(fmt.Sprintf("recursive accessor cancellation lost: %#v",failure))}
 }
}
`)
	generated := strings.Replace(result.Source, "package main\n", "package main\nimport (\"context\";\"reflect\";\"strings\";\"fmt\")\n", 1)
	generated = strings.Replace(generated, "\tinitialize()\n", "\tinitialize()\n\tcheckAccessorFaults()\n", 1) + harness
	binary := filepath.Join(t.TempDir(), "accessor-faults")
	if err := Build(generated, binary); err != nil {
		t.Fatal(err)
	}
	if output, err := exec.Command(binary).CombinedOutput(); err != nil {
		t.Fatalf("accessor fault contract: %v\n%s", err, output)
	}
}
