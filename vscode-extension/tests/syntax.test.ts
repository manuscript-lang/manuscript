import { describe, test, expect } from "bun:test";

// Load and test the TextMate grammar
const grammar = await Bun.file(
  new URL("../syntaxes/manuscript.tmLanguage.json", import.meta.url).pathname
).json();

describe("TextMate Grammar - Structure", () => {
  test("has correct scope name", () => {
    expect(grammar.scopeName).toBe("source.manuscript");
  });

  test("has correct name", () => {
    expect(grammar.name).toBe("Manuscript");
  });

  test("includes all required patterns", () => {
    const patterns = grammar.patterns.map((p: any) => p.include);
    expect(patterns).toContain("#comments");
    expect(patterns).toContain("#strings");
    expect(patterns).toContain("#numbers");
    expect(patterns).toContain("#keywords");
    expect(patterns).toContain("#constants");
    expect(patterns).toContain("#operators");
    expect(patterns).toContain("#functions");
    expect(patterns).toContain("#types");
    expect(patterns).toContain("#variables");
  });
});

describe("TextMate Grammar - Comments", () => {
  test("matches line comments", () => {
    const pattern = grammar.repository.comments.patterns[0];
    expect(pattern.match).toBe("//.*$");
    expect(pattern.name).toBe("comment.line.double-slash.manuscript");
  });
});

describe("TextMate Grammar - Strings", () => {
  const stringPatterns = grammar.repository.strings.patterns;

  test("matches raw triple-quoted strings", () => {
    const pattern = stringPatterns.find((p: any) => p.begin === 'r"""');
    expect(pattern).toBeDefined();
    expect(pattern.name).toBe("string.quoted.triple.manuscript");
  });

  test("matches triple-quoted strings with interpolation", () => {
    const pattern = stringPatterns.find((p: any) => p.begin === '"""' && p.patterns?.length > 0);
    expect(pattern).toBeDefined();
    expect(pattern.patterns.map((p: any) => p.include)).toContain("#string-interpolation");
  });

  test("matches raw strings", () => {
    const pattern = stringPatterns.find((p: any) => p.begin === 'r"');
    expect(pattern).toBeDefined();
    expect(pattern.name).toBe("string.quoted.double.raw.manuscript");
  });

  test("matches byte strings", () => {
    const pattern = stringPatterns.find((p: any) => p.begin === 'b"');
    expect(pattern).toBeDefined();
    expect(pattern.name).toBe("string.quoted.double.bytes.manuscript");
  });

  test("matches regular strings with interpolation", () => {
    const pattern = stringPatterns.find((p: any) => p.begin === '"' && p.patterns?.length > 0);
    expect(pattern).toBeDefined();
    expect(pattern.patterns.map((p: any) => p.include)).toContain("#string-interpolation");
  });
});

describe("TextMate Grammar - String Interpolation", () => {
  test("matches interpolation syntax", () => {
    const interpolation = grammar.repository["string-interpolation"].patterns[0];
    expect(interpolation.begin).toBe("(?<!\\\\)\\{");
    expect(interpolation.end).toBe("\\}");
  });
});

describe("TextMate Grammar - String Escapes", () => {
  test("matches escape sequences", () => {
    const escapes = grammar.repository["string-escapes"].patterns[0];
    expect(escapes.name).toBe("constant.character.escape.manuscript");
    // Should match \n, \r, \t, \\, \", \{, \}, \uXXXX, \u{X+}, \xXX
    expect(escapes.match).toContain("nrt");
  });
});

describe("TextMate Grammar - Numbers", () => {
  const numberPatterns = grammar.repository.numbers.patterns;

  test("matches hexadecimal numbers", () => {
    const pattern = numberPatterns.find((p: any) => p.name === "constant.numeric.hex.manuscript");
    expect(pattern).toBeDefined();
    expect(pattern.match).toBe("\\b0x[0-9a-fA-F][0-9a-fA-F_]*\\b");
  });

  test("matches binary numbers", () => {
    const pattern = numberPatterns.find((p: any) => p.name === "constant.numeric.binary.manuscript");
    expect(pattern).toBeDefined();
    expect(pattern.match).toBe("\\b0b[01][01_]*\\b");
  });

  test("matches float numbers", () => {
    const pattern = numberPatterns.find((p: any) => p.name === "constant.numeric.float.manuscript");
    expect(pattern).toBeDefined();
  });

  test("matches integer numbers", () => {
    const pattern = numberPatterns.find((p: any) => p.name === "constant.numeric.integer.manuscript");
    expect(pattern).toBeDefined();
  });
});

describe("TextMate Grammar - Keywords", () => {
  const keywordPatterns = grammar.repository.keywords.patterns;

  test("matches control flow keywords", () => {
    const pattern = keywordPatterns.find((p: any) => p.name === "keyword.control.manuscript");
    expect(pattern).toBeDefined();
    expect(pattern.match).toContain("if");
    expect(pattern.match).toContain("else");
    expect(pattern.match).toContain("for");
    expect(pattern.match).toContain("match");
    expect(pattern.match).toContain("return");
    expect(pattern.match).toContain("try");
    expect(pattern.match).toContain("catch");
    expect(pattern.match).toContain("spawn");
  });

  test("matches declaration keywords", () => {
    const pattern = keywordPatterns.find((p: any) => p.name === "keyword.declaration.manuscript");
    expect(pattern).toBeDefined();
    expect(pattern.match).toContain("fn");
    expect(pattern.match).toContain("type");
    expect(pattern.match).toContain("let");
    expect(pattern.match).toContain("var");
    expect(pattern.match).toContain("test");
    expect(pattern.match).toContain("sealed");
    expect(pattern.match).toContain("extends");
  });

  test("matches operator keywords", () => {
    const pattern = keywordPatterns.find((p: any) => p.name === "keyword.operator.manuscript");
    expect(pattern).toBeDefined();
    expect(pattern.match).toContain("and");
    expect(pattern.match).toContain("or");
    expect(pattern.match).toContain("not");
    expect(pattern.match).toContain("is");
    expect(pattern.match).toContain("as");
    expect(pattern.match).toContain("in");
  });
});

describe("TextMate Grammar - Constants", () => {
  const constantPatterns = grammar.repository.constants.patterns;

  test("matches true", () => {
    const pattern = constantPatterns.find((p: any) => p.name === "constant.language.boolean.true.manuscript");
    expect(pattern).toBeDefined();
    expect(pattern.match).toBe("\\btrue\\b");
  });

  test("matches false", () => {
    const pattern = constantPatterns.find((p: any) => p.name === "constant.language.boolean.false.manuscript");
    expect(pattern).toBeDefined();
    expect(pattern.match).toBe("\\bfalse\\b");
  });

  test("matches null", () => {
    const pattern = constantPatterns.find((p: any) => p.name === "constant.language.null.manuscript");
    expect(pattern).toBeDefined();
    expect(pattern.match).toBe("\\bnull\\b");
  });
});

describe("TextMate Grammar - Operators", () => {
  const operatorPatterns = grammar.repository.operators.patterns;

  test("matches spread operator", () => {
    const pattern = operatorPatterns.find((p: any) => p.name === "keyword.operator.spread.manuscript");
    expect(pattern).toBeDefined();
    expect(pattern.match).toBe("\\.\\.\\.");
  });

  test("matches range operator", () => {
    const pattern = operatorPatterns.find((p: any) => p.name === "keyword.operator.range.manuscript");
    expect(pattern).toBeDefined();
    expect(pattern.match).toBe("\\.\\.");
  });

  test("matches arrow operator", () => {
    const pattern = operatorPatterns.find((p: any) => p.name === "keyword.operator.arrow.manuscript");
    expect(pattern).toBeDefined();
    expect(pattern.match).toBe("=>");
  });

  test("matches nullish coalescing", () => {
    const pattern = operatorPatterns.find((p: any) => p.name === "keyword.operator.nullish.manuscript");
    expect(pattern).toBeDefined();
    expect(pattern.match).toBe("\\?\\?");
  });

  test("matches optional chaining", () => {
    const pattern = operatorPatterns.find((p: any) => p.name === "keyword.operator.optional-chain.manuscript");
    expect(pattern).toBeDefined();
    expect(pattern.match).toBe("\\?\\.");
  });

  test("matches comparison operators", () => {
    const pattern = operatorPatterns.find((p: any) => p.name === "keyword.operator.comparison.manuscript");
    expect(pattern).toBeDefined();
    expect(pattern.match).toContain("==");
    expect(pattern.match).toContain("!=");
  });

  test("matches pipe operator", () => {
    const pattern = operatorPatterns.find((p: any) => p.name === "keyword.operator.pipe.manuscript");
    expect(pattern).toBeDefined();
    expect(pattern.match).toBe("\\|");
  });
});

describe("TextMate Grammar - Functions", () => {
  const functionPatterns = grammar.repository.functions.patterns;

  test("matches function declarations", () => {
    const pattern = functionPatterns.find((p: any) => p.captures?.["2"]?.name === "entity.name.function.manuscript");
    expect(pattern).toBeDefined();
  });

  test("matches function calls", () => {
    const pattern = functionPatterns.find((p: any) => p.captures?.["1"]?.name === "entity.name.function.call.manuscript");
    expect(pattern).toBeDefined();
  });
});

describe("TextMate Grammar - Types", () => {
  const typePatterns = grammar.repository.types.patterns;

  test("matches type declarations", () => {
    const pattern = typePatterns.find((p: any) => p.captures?.["2"]?.name === "entity.name.type.manuscript");
    expect(pattern).toBeDefined();
  });

  test("matches primitive types", () => {
    const pattern = typePatterns.find((p: any) => p.name === "support.type.primitive.manuscript");
    expect(pattern).toBeDefined();
    expect(pattern.match).toContain("number");
    expect(pattern.match).toContain("string");
    expect(pattern.match).toContain("bool");
    expect(pattern.match).toContain("null");
    expect(pattern.match).toContain("bytes");
    expect(pattern.match).toContain("any");
    expect(pattern.match).toContain("void");
  });

  test("matches builtin types", () => {
    const pattern = typePatterns.find((p: any) => p.name === "support.type.builtin.manuscript");
    expect(pattern).toBeDefined();
    expect(pattern.match).toContain("list");
    expect(pattern.match).toContain("map");
    expect(pattern.match).toContain("set");
    expect(pattern.match).toContain("Channel");
    expect(pattern.match).toContain("Promise");
  });
});

describe("TextMate Grammar - Variables", () => {
  const variablePatterns = grammar.repository.variables.patterns;

  test("matches variable declarations", () => {
    const pattern = variablePatterns.find((p: any) => p.captures?.["2"]?.name === "variable.other.manuscript");
    expect(pattern).toBeDefined();
    expect(pattern.match).toContain("let");
    expect(pattern.match).toContain("var");
  });
});

describe("Language Configuration", () => {
  test("has line comment defined", async () => {
    const langConfig = await Bun.file(
      new URL("../language-configuration.json", import.meta.url).pathname
    ).json();
    expect(langConfig.comments.lineComment).toBe("//");
  });

  test("has brackets defined", async () => {
    const langConfig = await Bun.file(
      new URL("../language-configuration.json", import.meta.url).pathname
    ).json();
    expect(langConfig.brackets).toContainEqual(["{", "}"]);
    expect(langConfig.brackets).toContainEqual(["[", "]"]);
    expect(langConfig.brackets).toContainEqual(["(", ")"]);
  });

  test("has auto-closing pairs defined", async () => {
    const langConfig = await Bun.file(
      new URL("../language-configuration.json", import.meta.url).pathname
    ).json();
    expect(langConfig.autoClosingPairs).toContainEqual({ open: "{", close: "}" });
    expect(langConfig.autoClosingPairs).toContainEqual({ open: "[", close: "]" });
    expect(langConfig.autoClosingPairs).toContainEqual({ open: "(", close: ")" });
  });

  test("has indentation rules", async () => {
    const langConfig = await Bun.file(
      new URL("../language-configuration.json", import.meta.url).pathname
    ).json();
    expect(langConfig.indentationRules).toBeDefined();
    expect(langConfig.indentationRules.increaseIndentPattern).toContain("fn");
    expect(langConfig.indentationRules.increaseIndentPattern).toContain("type");
    expect(langConfig.indentationRules.increaseIndentPattern).toContain("if");
    expect(langConfig.indentationRules.increaseIndentPattern).toContain("for");
    expect(langConfig.indentationRules.increaseIndentPattern).toContain("match");
  });

  test("has folding set to offSide", async () => {
    const langConfig = await Bun.file(
      new URL("../language-configuration.json", import.meta.url).pathname
    ).json();
    expect(langConfig.folding.offSide).toBe(true);
  });

  test("has word pattern defined", async () => {
    const langConfig = await Bun.file(
      new URL("../language-configuration.json", import.meta.url).pathname
    ).json();
    expect(langConfig.wordPattern).toBe("[a-zA-Z_][a-zA-Z0-9_]*");
  });
});
