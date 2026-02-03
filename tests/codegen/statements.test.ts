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
});
