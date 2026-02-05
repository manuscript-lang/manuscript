import { describe, test, expect } from "bun:test";
import { compile, expectCompiled, compileCases } from "../helpers";

describe("CodeGen - Let Statements", () => {
  test("simple let", () => {
    expectCompiled("let x = 1", "const x = 1;");
  });

  test("let with destructuring", () => {
    expectCompiled("let {a, b} = obj", "const { a, b } = obj;");
  });

  test("let with array destructuring", () => {
    expectCompiled("let [x, y] = arr", "const [x, y] = arr;");
  });
});

describe("CodeGen - Var Statements", () => {
  test("simple var", () => {
    expectCompiled("var x = 1", "let x = 1;");
  });
});

describe("CodeGen - Assignment Statements", () => {
  test("simple assignment", () => {
    expectCompiled(`var x = 1
x = 2`, "x = 2;");
  });

  test("compound assignment", () => {
    expectCompiled(`var x = 1
x += 2`, "x += 2;");
  });
});

describe("CodeGen - If Statements", () => {
  test("if block", () => {
    const js = compile(`if true
  print(1)`);
    expect(js).toContain("if (true)");
    expect(js).toContain("{");
  });

  test("if-else", () => {
    const js = compile(`if true
  print(1)
else
  print(2)`);
    expect(js).toContain("} else {");
  });

  test("if-else-if chain", () => {
    const js = compile(`if x == 1
  print("one")
else if x == 2
  print("two")
else
  print("other")`);
    expect(js).toContain("else if");
  });

  test("if with implicit return", () => {
    const js = compile(`fn sign(n: number): string
  if n > 0
    "positive"
  else if n < 0
    "negative"
  else
    "zero"`);
    expect(js).toContain('return "positive"');
    expect(js).toContain('return "negative"');
    expect(js).toContain('return "zero"');
  });
});

describe("CodeGen - For Statements", () => {
  test("for-in loop", () => {
    const js = compile(`for x in items
  print(x)`);
    expect(js).toContain("for await (const x of items)");
  });

  test("for with range", () => {
    const js = compile(`for i in 0..10
  print(i)`);
    expect(js).toContain("for (let i = 0; i < 10; i++)");
  });

  test("infinite loop", () => {
    const js = compile(`for
  print(1)
  break`);
    expect(js).toContain("while (true)");
  });
});

describe("CodeGen - Match Statements", () => {
  test("simple match", () => {
    const js = compile(`match x
  1 => print("one")
  _ => print("other")`);
    expect(js).toContain("if (");
  });

  test("match with type pattern", () => {
    const js = compile(`type Foo
  x: number
match val
  Foo as f => print(f.x)
  _ => print("other")`);
    expect(js).toContain("instanceof Foo");
    expect(js).toContain("const f =");
  });

  test("match with range pattern", () => {
    const js = compile(`match n
  1..10 => print("small")
  _ => print("big")`);
    expect(js).toContain(">= 1");
    expect(js).toContain("<= 10");
  });

  test("match with array pattern", () => {
    const js = compile(`match arr
  [x, y] => print(x + y)
  _ => print("no match")`);
    expect(js).toContain("Array.isArray");
  });

  test("match with object pattern", () => {
    const js = compile(`match obj
  {name, age} => print(name)
  _ => print("no match")`);
    expect(js).toContain('typeof');
    expect(js).toContain('=== "object"');
  });

  test("match with guard", () => {
    const js = compile(`match x
  n if n > 0 => print("positive")
  _ => print("non-positive")`);
    expect(js).toContain("n > 0");
  });

  test("match with implicit return in function", () => {
    const js = compile(`fn classify(x: number): string
  match x
    0 => "zero"
    n if n > 0 => "positive"
    _ => "negative"`);
    expect(js).toContain('return "zero"');
    expect(js).toContain('return "positive"');
  });
});

describe("CodeGen - Return Statements", () => {
  test("return value", () => {
    expectCompiled(`fn f()
  return 1`, "return 1;");
  });

  test("return void", () => {
    expectCompiled(`fn f()
  return`, "return;");
  });
});

describe("CodeGen - Break/Continue", () => {
  test("break", () => {
    expectCompiled(`for
  break`, "break;");
  });

  test("continue", () => {
    expectCompiled(`for x in items
  continue`, "continue;");
  });
});

describe("CodeGen - Try/Catch", () => {
  test("try-catch", () => {
    const js = compile(`try
  throw("error")
catch e
  print(e)`);
    expect(js).toContain("try {");
    expect(js).toContain("} catch (e) {");
  });
});

describe("CodeGen - Throw", () => {
  test("throw", () => {
    expectCompiled('throw("error")', 'throw "error";');
  });
});

describe("CodeGen - With Statements", () => {
  test("with context", () => {
    const js = compile(`with ctx()
  print(1)`);
    // With statements now use try/finally for cleanup
    expect(js).toContain("try {");
    expect(js).toContain("} finally {");
    // Check for exit() call on context
    expect(js).toContain("?.exit");
  });

  test("with named binding", () => {
    const js = compile(`context Ctx
  value: number
with let c = Ctx(42)
  print(c.value)`);
    expect(js).toContain("const c =");
    expect(js).toContain("c.value");
  });

  test("with implicit return", () => {
    const js = compile(`context Ctx
  value: number
fn getValue(): number
  with let c = Ctx(42)
    c.value`);
    expect(js).toContain("return c.value");
  });
});

describe("CodeGen - Destructuring Patterns", () => {
  test("object destructuring with rename", () => {
    expectCompiled("let {x: a, y: b} = obj", "x: a, y: b");
  });

  test("array destructuring with rest", () => {
    expectCompiled("let [first, ...rest] = arr", "[first, ...rest]");
  });

  test("nested destructuring", () => {
    expectCompiled("let {a: {b}} = obj", "a: { b }");
  });
});

describe("CodeGen - Yield Statements", () => {
  test("yield in generator", () => {
    const js = compile(`fn gen()
  yield 1
  yield 2`);
    expect(js).toContain("yield 1");
    expect(js).toContain("yield 2");
    expect(js).toContain("function*");
  });
});

describe("CodeGen - Defer Statements", () => {
  test("defer in with block", () => {
    const js = compile(`context Ctx
  value: number
with let c = Ctx(42)
  defer print("cleanup")
  print(c.value)`);
    expect(js).toContain("finally {");
    expect(js).toContain('print("cleanup")');
  });
});
