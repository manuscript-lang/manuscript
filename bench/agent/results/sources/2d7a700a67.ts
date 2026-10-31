// Read stdin, write stdout. See TASK.md.
import readFileSync from 'node:fs';

class ParseError extends Error {}

type Token = { kind: 'num'; value: bigint } | { kind: 'op'; op: string } | { kind: 'end' };

function tokenize(line: string): Token[] {
  const tokens: Token[] = [];
  let i = 0;
  while (i < line.length) {
    const c = line[i];
    if (c === ' ' || c === '\t' || c === '\r') {
      i++;
    } else if (c >= '0' && c <= '9') {
      let j = i;
      while (j < line.length && line[j] >= '0' && line[j] <= '9') j++;
      tokens.push({ kind: 'num', value: BigInt(line.slice(i, j)) });
      i = j;
    } else if ('+-*/()'.includes(c)) {
      tokens.push({ kind: 'op', op: c });
      i++;
    } else {
      throw new ParseError();
    }
  }
  tokens.push({ kind: 'end' });
  return tokens;
}

// Evaluates while parsing. Division by zero sets a flag instead of aborting, so every
// division is still evaluated and a later syntax error still takes precedence.
class Parser {
  private pos = 0;
  private readonly tokens: Token[];
  divByZero = false;

  constructor(tokens: Token[]) {
    this.tokens = tokens;
  }

  parse(): bigint {
    const value = this.expr();
    if (this.peek().kind !== 'end') throw new ParseError();
    return value;
  }

  private peek(): Token {
    return this.tokens[this.pos];
  }

  private isOp(op: string): boolean {
    const t = this.peek();
    return t.kind === 'op' && t.op === op;
  }

  // expr := term (('+' | '-') term)*
  private expr(): bigint {
    let value = this.term();
    while (this.isOp('+') || this.isOp('-')) {
      const op = (this.tokens[this.pos++] as { op: string }).op;
      const rhs = this.term();
      value = op === '+' ? value + rhs : value - rhs;
    }
    return value;
  }

  // term := unary (('*' | '/') unary)*
  private term(): bigint {
    let value = this.unary();
    while (this.isOp('*') || this.isOp('/')) {
      const op = (this.tokens[this.pos++] as { op: string }).op;
      const rhs = this.unary();
      if (op === '*') {
        value = value * rhs;
      } else if (rhs === 0n) {
        this.divByZero = true;
        value = 0n;
      } else {
        value = value / rhs; // BigInt division truncates toward zero
      }
    }
    return value;
  }

  // unary := '-' unary | primary
  private unary(): bigint {
    if (this.isOp('-')) {
      this.pos++;
      return -this.unary();
    }
    return this.primary();
  }

  // primary := number | '(' expr ')'
  private primary(): bigint {
    const t = this.peek();
    if (t.kind === 'num') {
      this.pos++;
      return t.value;
    }
    if (this.isOp('(')) {
      this.pos++;
      const value = this.expr();
      if (!this.isOp(')')) throw new ParseError();
      this.pos++;
      return value;
    }
    throw new ParseError();
  }
}

function evaluate(line: string): string {
  try {
    const parser = new Parser(tokenize(line));
    const value = parser.parse();
    return parser.divByZero ? 'error: division by zero' : value.toString();
  } catch (e) {
    if (e instanceof ParseError) return 'error: syntax';
    throw e;
  }
}

const input = readFileSync(0, 'utf8');
const out: string[] = [];
for (const line of input.split('\n')) {
  if (line.trim() === '') continue;
  out.push(evaluate(line));
}
if (out.length > 0) process.stdout.write(out.join('\n') + '\n');
