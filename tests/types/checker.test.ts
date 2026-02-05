import { describe, test, expect } from "bun:test";
import { checkOk, checkFails, check } from "../helpers";

describe("Type Checker - Variable Scoping", () => {
  test("variable in scope", () => {
    checkOk(`let x = 1
x + 1`);
  });

  test("variable out of scope", () => {
    checkFails("y + 1", "Unknown identifier");
  });

  test("variable redefinition in same scope", () => {
    checkFails(`let x = 1
let x = 2`, "already defined");
  });

  test("variable shadowing in child scope", () => {
    checkOk(`let x = 1
if true
  let x = 2
  x + 1`);
  });
});

describe("Type Checker - Mutability", () => {
  test("cannot assign to let", () => {
    checkFails(`let x = 1
x = 2`, "Cannot assign to immutable");
  });

  test("can assign to var", () => {
    checkOk(`var x = 1
x = 2`);
  });

  test("compound assignment to var", () => {
    checkOk(`var x = 1
x += 2`);
  });
});

describe("Type Checker - Type Compatibility", () => {
  test("number to number", () => {
    checkOk("let x: number = 42");
  });

  test("string to string", () => {
    checkOk('let x: string = "hello"');
  });

  test("number to string fails", () => {
    checkFails('let x: string = 42', "not assignable");
  });

  test("string to number fails", () => {
    checkFails('let x: number = "hello"', "not assignable");
  });
});

describe("Type Checker - Function Declarations", () => {
  test("function with correct return type", () => {
    checkOk(`fn add(a: number, b: number): number
  a + b`);
  });

  test("function called with correct args", () => {
    checkOk(`fn double(x: number): number
  x * 2
double(5)`);
  });

  test("function with capabilities", () => {
    checkOk(`type MyFilesystem
  Context
  fn read(path: string): string
fn read_file(path: string) using (fs: MyFilesystem)
  fs.read(path)`);
  });
});

describe("Type Checker - Type Declarations", () => {
  test("simple type", () => {
    checkOk(`type User
  name: string
  age: number`);
  });

  test("type with optional field", () => {
    checkOk(`type User
  name: string
  email?: string`);
  });

  test("type with default value", () => {
    checkOk(`type Config
  timeout: number = 1000`);
  });

  test("type with method", () => {
    checkOk(`type Counter
  value: number = 0
  fn increment()
    value = value + 1`);
  });

  test("type method can access fields", () => {
    checkOk(`type Person
  name: string
  age: number
  fn greet(): string
    "Hello, " + name`);
  });

  test("type method can access parameters", () => {
    checkOk(`type Greeter
  name: string
  fn greet(person: string): string
    "Hello, " + person + " from " + name`);
  });

  test("type method unknown identifier fails", () => {
    checkFails(`type Foo
  fn bar()
    x = unknown + 1`, "Unknown identifier");
  });

  test("type method scope resolves parameters before fields", () => {
    // Parameter 'name' should shadow field 'name'
    checkOk(`type Person
  name: string
  fn greet(name: string): string
    "Hello, " + name`);
  });

  test("computed field can reference other fields", () => {
    checkOk(`type Circle
  radius: number
  diameter: () => radius * 2`);
  });

  test("computed field unknown identifier fails", () => {
    checkFails(`type Circle
  radius: number
  area: () => pi * radius * radius`, "Unknown identifier");
  });

  test("field default value type mismatch fails", () => {
    checkFails(`type Config
  count: number = "hello"`, "not assignable");
  });

  test("method return type mismatch fails", () => {
    checkFails(`type Foo
  fn bar(): number
    "not a number"`, "not assignable");
  });

  test("unknown property on string fails", () => {
    checkFails(`let s = "hello"
s.unknown`, "does not exist on type 'string'");
  });

  test("unknown property on number fails", () => {
    checkFails(`let n = 42
n.value`, "does not exist on type 'number'");
  });

  test("unknown property on bool fails", () => {
    checkFails(`let b = true
b.flag`, "does not exist on type 'bool'");
  });

  test("unknown property on list fails", () => {
    checkFails(`let a = [1,2,3]
a.unknown`, "does not exist on type 'list'");
  });

  test("known string method ok", () => {
    checkOk(`let s = "hello"
print(s.upper())`);
  });

  test("known list method ok", () => {
    checkOk(`let a = [1,2,3]
print(a.length)`);
  });

  test("generic type constructor infers correct type", () => {
    checkOk(`type Container[T]
  value: T
let c = Container[string]("hello")
print(c.value)`);
  });

  test("generic type unknown property fails", () => {
    checkFails(`type Container[T]
  value: T
let c = Container[string]("hello")
print(c.unknown)`, "does not exist");
  });

  test("generic type with method", () => {
    checkOk(`type Box[T]
  value: T
  fn get(): T
    value
let b = Box[number](42)
print(b.get())`);
  });

  test("nested type access", () => {
    checkOk(`type Inner
  name: string
type Outer
  inner: Inner = Inner("test")
let o = Outer()
print(o.inner.name)`);
  });

  test("nested type unknown property fails", () => {
    checkFails(`type Inner
  name: string
type Outer
  inner: Inner = Inner("test")
let o = Outer()
print(o.inner.unknown)`, "does not exist");
  });

  test("method can modify and return field", () => {
    checkOk(`type Counter
  value: number = 0
  fn increment(): number
    value = value + 1
    value`);
  });

  test("template string field access in method", () => {
    checkOk(`type Person
  name: string
  age: number
  fn describe(): string
    "{name} is {age} years old"`);
  });

  test("template string with unknown identifier fails", () => {
    checkFails(`type Person
  name: string
  fn describe(): string
    "{unknown} is here"`, "Unknown identifier");
  });
});

describe("Type Checker - Control Flow", () => {
  test("if statement", () => {
    checkOk(`if true
  print("yes")`);
  });

  test("if-else", () => {
    checkOk(`if true
  print("yes")
else
  print("no")`);
  });

  test("for loop", () => {
    checkOk(`for i in 0..10
  print(i)`);
  });

  test("break outside loop fails", () => {
    checkFails("break", "outside of loop");
  });

  test("continue outside loop fails", () => {
    checkFails("continue", "outside of loop");
  });

  test("break inside loop ok", () => {
    checkOk(`for i in 0..10
  if i == 5 then break`);
  });
});

describe("Type Checker - Match Statements", () => {
  test("simple match", () => {
    checkOk(`match 1
  1 => "one"
  2 => "two"
  _ => "other"`);
  });

  test("match with binding", () => {
    checkOk(`match 42
  x => x + 1`);
  });
});

describe("Type Checker - Error Handling", () => {
  test("try-catch", () => {
    checkOk(`try
  throw("error")
catch e
  print(e.message)`);
  });

  test("throw", () => {
    checkOk('throw("error message")');
  });
});

describe("Type Checker - With Statement", () => {
  test("with statement", () => {
    // Define a context function first
    checkOk(`fn production()
  print("prod")
with production()
  print("running")`);
  });

  test("with let binding", () => {
    // New syntax: with let name = expr
    checkOk(`fn Trace(name: string)
  print(name)
with let t = Trace("op")
  print("traced")`);
  });
});

describe("Type Checker - Test Declarations", () => {
  test("simple test", () => {
    checkOk(`test "description"
  assert true`);
  });
});

describe("Type Checker - Warnings", () => {
  test("collects warnings", () => {
    const result = check(`fn needs_fs() using (fs: Filesystem)
  fs.read("file.txt")
needs_fs()`);
    // Should have a warning about capability
    expect(result.warnings.length).toBeGreaterThan(0);
  });
});

// ============================================
// Function Call Validation
// ============================================

describe("Type Checker - Function Call Arguments", () => {
  test("too few arguments fails", () => {
    checkFails(`fn add(a: number, b: number): number
  a + b
add(1)`, "Expected at least 2");
  });

  test("too many arguments fails", () => {
    checkFails(`fn double(x: number): number
  x * 2
double(1, 2, 3)`, "Expected at most 1");
  });

  test("wrong argument type fails", () => {
    checkFails(`fn greet(name: string): string
  "Hello " + name
greet(42)`, "not assignable");
  });

  test("mixed positional and named arguments fails", () => {
    checkFails(`fn triple(a: number, b: number, c: number): number
  a + b + c
let x = triple(10, c: 30, b: 20)`, "Cannot mix positional and named");
  });

  test("optional parameter can be omitted", () => {
    checkOk(`fn greet(name: string, greeting?: string): string
  "hi"
greet("Alice")`);
  });

  test("optional parameter can be provided", () => {
    checkOk(`fn greet(name: string, greeting?: string): string
  "hi"
greet("Alice", "Hello")`);
  });

  test("rest parameter accepts multiple args", () => {
    checkOk(`fn sum(...nums: list[number]): number
  0
sum(1, 2, 3, 4, 5)`);
  });

  test("type constructor with correct args", () => {
    checkOk(`type Point
  x: number
  y: number
let p = Point(3, 4)`);
  });

  test("type constructor with too few args fails", () => {
    checkFails(`type Point
  x: number
  y: number
let p = Point(3)`, "at least 2");
  });

  test("type constructor with default fields", () => {
    checkOk(`type Config
  name: string
  value: number = 0
let c = Config("test")`);
  });

  test("type constructor with wrong type fails", () => {
    checkFails(`type Point
  x: number
  y: number
let p = Point("a", "b")`, "not assignable");
  });

  test("type constructor mixed positional and named fails", () => {
    checkFails(`type Point
  x: number
  y: number
let p = Point(1, y: 2)`, "Cannot mix positional and named");
  });
});

// ============================================
// Operator Type Checking
// ============================================

describe("Type Checker - Arithmetic Operators", () => {
  test("number + number ok", () => {
    checkOk("let x = 1 + 2");
  });

  test("string + string ok", () => {
    checkOk('let x = "a" + "b"');
  });

  test("string + number ok (coercion)", () => {
    checkOk('let x = "a" + 1');
  });

  test("number - number ok", () => {
    checkOk("let x = 5 - 3");
  });

  test("string - number fails", () => {
    checkFails('let x = "a" - 1', "requires number");
  });

  test("number * number ok", () => {
    checkOk("let x = 2 * 3");
  });

  test("string * number fails", () => {
    checkFails('let x = "a" * 2', "requires number");
  });

  test("number / number ok", () => {
    checkOk("let x = 10 / 2");
  });

  test("bool / number fails", () => {
    checkFails("let x = true / 2", "requires number");
  });

  test("number % number ok", () => {
    checkOk("let x = 10 % 3");
  });

  test("number ^ number ok", () => {
    checkOk("let x = 2 ^ 3");
  });

  test("unary minus on number ok", () => {
    checkOk("let x = -5");
  });

  test("unary minus on string fails", () => {
    checkFails('let x = -"hello"', "requires number");
  });
});

describe("Type Checker - Comparison Operators", () => {
  test("number < number ok", () => {
    checkOk("let x = 1 < 2");
  });

  test("string < string ok", () => {
    checkOk('let x = "a" < "b"');
  });

  test("number == number ok", () => {
    checkOk("let x = 1 == 2");
  });

  test("optional number < number ok", () => {
    checkOk(`let x: number? = 5
let y = x < 10`);
  });
});

// ============================================
// Index Access Validation
// ============================================

describe("Type Checker - Index Access", () => {
  test("list with number index ok", () => {
    checkOk("let x = [1, 2, 3][0]");
  });

  test("list with string index fails", () => {
    checkFails('let x = [1, 2, 3]["a"]', "not assignable to 'number'");
  });

  test("string with number index ok", () => {
    checkOk('let x = "hello"[0]');
  });

  test("string with string index fails", () => {
    checkFails('let x = "hello"["a"]', "not assignable to 'number'");
  });

  test("map with correct key type ok", () => {
    checkOk(`let m: map[string, number] = {"a": 1}
let x = m["a"]`);
  });

  test("slice with number indices ok", () => {
    checkOk("let x = [1, 2, 3][0:2]");
  });
});

// ============================================
// Member Access Validation
// ============================================

describe("Type Checker - Member Access", () => {
  test("access existing property ok", () => {
    checkOk(`type User
  name: string
let u = User("Alice")
let n = u.name`);
  });

  test("access non-existent property fails", () => {
    checkFails(`type User
  name: string
let u = User("Alice")
let x = u.age`, "does not exist");
  });

  test("optional chaining on unknown property ok", () => {
    checkOk(`type User
  name: string
let u = User("Alice")
let x = u?.unknown`);
  });

  test("string length ok", () => {
    checkOk('let x = "hello".length');
  });

  test("list length ok", () => {
    checkOk("let x = [1, 2, 3].length");
  });

  test("list push ok", () => {
    checkOk(`var list = [1, 2, 3]
list.push(4)`);
  });

  test("string methods ok", () => {
    checkOk('let x = "hello".upper()');
  });
});

// ============================================
// Type Narrowing
// ============================================

describe("Type Checker - Type Narrowing", () => {
  test("is check narrows type in then branch", () => {
    checkOk(`fn process(x: number or string): number
  if x is number
    return x + 1
  return 0`);
  });

  test("null check narrows optional type", () => {
    checkOk(`fn process(x: number?): number
  if x != null
    return x + 1
  return 0`);
  });

  test("negated is check narrows in else", () => {
    checkOk(`fn process(x: number or string): string
  if not (x is string)
    return "number"
  return x + "!"`);
  });
});

// ============================================
// Match Exhaustiveness
// ============================================

describe("Type Checker - Match Exhaustiveness", () => {
  test("match with wildcard is exhaustive", () => {
    const result = check(`match 1
  1 => "one"
  _ => "other"`);
    // Should not warn about exhaustiveness
    expect(result.warnings.some(w => w.includes("exhaustive"))).toBe(false);
  });

  test("match with identifier pattern is exhaustive", () => {
    const result = check(`match 1
  x => x + 1`);
    expect(result.warnings.some(w => w.includes("exhaustive"))).toBe(false);
  });

  test("match on bool without both cases warns", () => {
    const result = check(`let b = true
match b
  true => "yes"`);
    expect(result.errors.some(e => e.message.includes("exhaustive"))).toBe(true);
  });

  test("match on bool with both cases ok", () => {
    const result = check(`let b = true
match b
  true => "yes"
  false => "no"`);
    expect(result.warnings.some(w => w.includes("exhaustive"))).toBe(false);
  });
});

// ============================================
// Return Statement Validation
// ============================================

describe("Type Checker - Return Statements", () => {
  test("return outside function fails", () => {
    checkFails("return 42", "outside of function");
  });

  test("return with wrong type fails", () => {
    checkFails(`fn get_num(): number
  return "hello"`, "not assignable to type");
  });

  test("empty return in void function ok", () => {
    checkOk(`fn do_nothing(): void
  return`);
  });

  test("return with value in void function fails", () => {
    // Void functions should not return values
    checkFails(`fn log_and_return(): void
  return 42`, "not assignable to type");
  });
});

// ============================================
// Generator Validation
// ============================================

describe("Type Checker - Generators", () => {
  test("yield inside generator ok", () => {
    checkOk(`fn gen()
  yield 1
  yield 2`);
  });

});

describe("Type Checker - Break/Continue", () => {
  test("break outside loop fails", () => {
    checkFails(`fn f(): number
  break
  1`, "break");
  });
  test("continue outside loop fails", () => {
    checkFails(`fn f(): number
  continue
  1`, "continue");
  });
});

describe("Type Checker - Defer", () => {
  test("defer runs body", () => {
    checkOk(`fn f(): number
  defer 1 + 1
  42`);
  });
});

describe("Type Checker - Match patterns", () => {
  test("match with range pattern", () => {
    checkOk(`let x = 5
match x
  1..10 => "low"
  _ => "other"`);
  });
  test("match with object pattern on map", () => {
    checkOk(`let m: map[string, number] = {"a": 1}
match m
  {} => 0
  _ => 1`);
  });
  test("match with array pattern and rest", () => {
    checkOk(`let nums = [1, 2, 3]
match nums
  [a, ...rest] => a + rest.length
  _ => 0`);
  });
  test("match literal pattern mismatch fails", () => {
    checkFails(`match 42
  "hello" => 1
  _ => 0`, "cannot match");
  });
  test("match type pattern incompatible fails", () => {
    checkFails(`match "str"
  number as n => n
  _ => 0`, "not compatible");
  });
  test("match rest pattern on non-list fails", () => {
    checkFails(`let n = 42
match n
  [a, ...r] => a
  _ => 0`, "rest");
  });
  test("match object pattern on non-object fails", () => {
    checkFails(`match 42
  {x} => x
  _ => 0`, "object");
  });
  test("match union with optional and type pattern", () => {
    checkOk(`let x: number? = 1
match x
  null => 0
  n => n`);
  });
});

describe("Type Checker - Using clause", () => {
  test("using non-context type fails", () => {
    checkFails(`type NotContext
  x: number
fn f(): number using (n: NotContext)
  0`, "context type");
  });
});

describe("Type Checker - Unreachable code", () => {
  test("code after return type-checks and may warn", () => {
    const result = check(`fn f(): number
  return 1
  let x = 2`);
    expect(result.errors).toHaveLength(0);
    expect(Array.isArray(result.warnings)).toBe(true);
  });
});

describe("Type Checker - Spawn", () => {
  test("spawn as bare statement fails", () => {
    checkFails(`fn f(): number
  spawn print(1)
  42`, "spawn result must be used");
  });
});

describe("Type Checker - Return outside function", () => {
  test("return at top level fails", () => {
    checkFails(`return 1`, "return");
  });
});

describe("Type Checker - Match guard and exhaustiveness", () => {
  test("match guard must be bool", () => {
    checkFails(`match 1
  x if 1 => x
  _ => 0`, "Guard");
  });
  test("match on optional without null case fails", () => {
    checkFails(`let x: number? = 1
match x
  number as n => n`, "exhaustive");
  });
  test("match on bool without both cases fails", () => {
    checkFails(`let b = true
match b
  true => 1`, "exhaustive");
  });
});

describe("Type Checker - Var redefinition", () => {
  test("var redefinition in same scope fails", () => {
    checkFails(`fn f(): number
  var x = 1
  var x = 2
  x`, "already defined");
  });
});
