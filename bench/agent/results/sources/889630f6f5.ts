// Read stdin, write stdout. See TASK.md.
import { readFileSync } from "node:fs";

type Node =
  | { kind: "num"; value: bigint }
  | { kind: "neg"; operand: Node }
  | { kind: "bin"; op: "+" | "-" | "*" | "/"; left: Node; right: Node };

class SyntaxError_ extends Error {}

type Token =
  | { kind: "num"; value: bigint }
  | { kind: "op"; op: "+" | "-" | "*" | "/" }
  | { kind: "lparen" }
  | { kind: "rparen" };

function tokenize(line: string): Token[] {
  const tokens: Token[] = [];
  let i = 0;
  while (i < line.length) {
    const c = line[i];
    if (c === " " || c === "\t") {
      i++;
    } else if (c >= "0" && c <= "9") {
      let j = i;
      while (j < line.length && line[j] >= "0" && line[j] <= "9") j++;
      tokens.push({ kind: "num", value: BigInt(line.slice(i, j)) });
      i = j;
    } else if (c === "+" || c === "-" || c === "*" || c === "/") {
      tokens.push({ kind: "op", op: c });
      i++;
    } else if (c === "(") {
      tokens.push({ kind: "lparen" });
      i++;
    } else if (c === ")") {
      tokens.push({ kind: "rparen" });
      i++;
    } else {
      throw new SyntaxError_("unknown character");
    }
  }
  return tokens;
}

// Grammar:
//   expr    := term (('+' | '-') term)*
//   term    := unary (('*' | '/') unary)*
//   unary   := '-' unary | primary
//   primary := NUMBER | '(' expr ')'
function parse(tokens: Token[]): Node {
  let pos = 0;

  const peek = (): Token | undefined => tokens[pos];

  function parseExpr(): Node {
    let left = parseTerm();
    for (;;) {
      const t = peek();
      if (t && t.kind === "op" && (t.op === "+" || t.op === "-")) {
        pos++;
        const right = parseTerm();
        left = { kind: "bin", op: t.op, left, right };
      } else {
        return left;
      }
    }
  }

  function parseTerm(): Node {
    let left = parseUnary();
    for (;;) {
      const t = peek();
      if (t && t.kind === "op" && (t.op === "*" || t.op === "/")) {
        pos++;
        const right = parseUnary();
        left = { kind: "bin", op: t.op, left, right };
      } else {
        return left;
      }
    }
  }

  function parseUnary(): Node {
    const t = peek();
    if (t && t.kind === "op" && t.op === "-") {
      pos++;
      return { kind: "neg", operand: parseUnary() };
    }
    return parsePrimary();
  }

  function parsePrimary(): Node {
    const t = peek();
    if (!t) throw new SyntaxError_("unexpected end");
    if (t.kind === "num") {
      pos++;
      return { kind: "num", value: t.value };
    }
    if (t.kind === "lparen") {
      pos++;
      const inner = parseExpr();
      const close = peek();
      if (!close || close.kind !== "rparen") throw new SyntaxError_("expected )");
      pos++;
      return inner;
    }
    throw new SyntaxError_("unexpected token");
  }

  const root = parseExpr();
  if (pos !== tokens.length) throw new SyntaxError_("trailing tokens");
  return root;
}

// Evaluates the whole tree (no short-circuit). A division by zero sets `state.divZero`
// and yields 0 so evaluation continues; the caller reports the error afterwards.
function evaluate(node: Node, state: { divZero: boolean }): bigint {
  switch (node.kind) {
    case "num":
      return node.value;
    case "neg":
      return -evaluate(node.operand, state);
    case "bin": {
      const a = evaluate(node.left, state);
      const b = evaluate(node.right, state);
      switch (node.op) {
        case "+":
          return a + b;
        case "-":
          return a - b;
        case "*":
          return a * b;
        case "/":
          if (b === 0n) {
            state.divZero = true;
            return 0n;
          }
          return a / b; // BigInt division truncates toward zero
      }
    }
  }
}

function processLine(line: string): string | null {
  let tokens: Token[];
  let ast: Node;
  try {
    tokens = tokenize(line);
    if (tokens.length === 0) return null;
    ast = parse(tokens);
  } catch (e) {
    if (e instanceof SyntaxError_) return "error: syntax";
    throw e;
  }
  const state = { divZero: false };
  const value = evaluate(ast, state);
  if (state.divZero) return "error: division by zero";
  return value.toString();
}

const input = readFileSync(0, "utf8");
const out: string[] = [];
for (const rawLine of input.split("\n")) {
  const line = rawLine.endsWith("\r") ? rawLine.slice(0, -1) : rawLine;
  const result = processLine(line);
  if (result !== null) out.push(result);
}
if (out.length > 0) process.stdout.write(out.join("\n") + "\n");
