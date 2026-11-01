// Two-pass assembler and virtual machine for the assembler-vm task. See TASK.md.
import { readFileSync } from 'node:fs';

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

class AsmError extends Error {}
class Trap extends Error {}

function asmErr(msg: string): AsmError {
  return new AsmError(msg);
}

// Line currently being processed; used to report assembler errors.
let curLine = 0;

// ---------------------------------------------------------------------------
// Lexical helpers
// ---------------------------------------------------------------------------

const REG_INDEX = new Map<string, number>([
  ['r0', 0], ['r1', 1], ['r2', 2], ['r3', 3], ['r4', 4], ['r5', 5], ['r6', 6], ['r7', 7],
  ['sp', 8], ['bp', 9],
]);

const ESC: Record<string, number> = { n: 10, t: 9, '0': 0, '\\': 92, "'": 39, '"': 34 };
const CHAR_RE = /^'(\\.|[^\\'])'/;
const IDENT_RE = /^[A-Za-z_][A-Za-z0-9_.]*$/;
const LABEL_RE = /^([A-Za-z_][A-Za-z0-9_.]*)\s*:/;

// Remove a `;` comment, respecting string and character literals.
function stripComment(line: string): string {
  let i = 0;
  while (i < line.length) {
    const c = line[i];
    if (c === '"') {
      i++;
      while (i < line.length && line[i] !== '"') {
        if (line[i] === '\\') i++;
        i++;
      }
      i++;
      continue;
    }
    if (c === "'") {
      const m = CHAR_RE.exec(line.slice(i));
      i += m ? m[0].length : 1;
      continue;
    }
    if (c === ';') return line.slice(0, i);
    i++;
  }
  return line;
}

// Split at commas that are outside brackets and character literals.
function splitOperands(rest: string): string[] {
  if (rest.trim() === '') return [];
  const out: string[] = [];
  let cur = '';
  let depth = 0;
  let i = 0;
  while (i < rest.length) {
    const c = rest[i];
    if (c === "'") {
      const m = CHAR_RE.exec(rest.slice(i));
      if (m) {
        cur += m[0];
        i += m[0].length;
        continue;
      }
    }
    if (c === '[') depth++;
    else if (c === ']' && depth > 0) depth--;
    if (c === ',' && depth === 0) {
      out.push(cur.trim());
      cur = '';
      i++;
      continue;
    }
    cur += c;
    i++;
  }
  out.push(cur.trim());
  return out;
}

// ---------------------------------------------------------------------------
// Expressions
// ---------------------------------------------------------------------------

type Sym =
  | { type: 'label'; sec: 'text' | 'data'; val: number }
  | { type: 'equ'; text: string; state: number; val: number };

const symtab = new Map<string, Sym>();

function symValue(name: string): number {
  const e = symtab.get(name);
  if (!e) throw asmErr(`undefined symbol '${name}'`);
  if (e.type === 'label') return e.val;
  if (e.state === 2) return e.val;
  if (e.state === 1) throw asmErr(`circular definition of '${name}'`);
  e.state = 1;
  e.val = evalExpr(e.text);
  e.state = 2;
  return e.val;
}

function charValue(lit: string, bad: () => AsmError): number {
  const inner = lit.slice(1, -1);
  if (inner[0] === '\\') {
    if (inner.length !== 2 || !(inner[1] in ESC)) throw bad();
    return ESC[inner[1]];
  }
  const bytes = Buffer.from(inner, 'utf8');
  if (bytes.length !== 1) throw bad();
  return bytes[0];
}

function numLiteral(tok: string, bad: () => AsmError): number {
  if (!/^(0x[0-9a-fA-F]+|0b[01]+|[0-9]+)$/.test(tok)) throw bad();
  const big = BigInt(tok);
  if (big > 4294967295n) throw asmErr('immediate out of range');
  return Number(BigInt.asIntN(32, big));
}

// Evaluate an expression: optional leading sign, terms separated by + or -,
// left to right with 32-bit wraparound.
function evalExpr(text: string, errText: string = text): number {
  const bad = () => asmErr(`invalid expression '${errText.trim()}'`);
  const s = text.trim();
  let i = 0;
  let total = 0;
  let sign = 1;
  const skip = () => {
    while (i < s.length && /\s/.test(s[i])) i++;
  };
  skip();
  if (s[i] === '+' || s[i] === '-') {
    if (s[i] === '-') sign = -1;
    i++;
  }
  for (;;) {
    skip();
    if (i >= s.length) throw bad();
    let v: number;
    if (s[i] === "'") {
      const m = CHAR_RE.exec(s.slice(i));
      if (!m) throw bad();
      v = charValue(m[0], bad);
      i += m[0].length;
    } else if (/[0-9]/.test(s[i])) {
      const m = /^[0-9A-Za-z_.]+/.exec(s.slice(i))!;
      v = numLiteral(m[0], bad);
      i += m[0].length;
    } else if (/[A-Za-z_]/.test(s[i])) {
      const m = /^[A-Za-z_][A-Za-z0-9_.]*/.exec(s.slice(i))!;
      v = symValue(m[0]);
      i += m[0].length;
    } else {
      throw bad();
    }
    total = (total + sign * v) | 0;
    skip();
    if (i >= s.length) break;
    if (s[i] === '+') sign = 1;
    else if (s[i] === '-') sign = -1;
    else throw bad();
    i++;
  }
  return total | 0;
}

// ---------------------------------------------------------------------------
// Operands (syntax, pass 1)
// ---------------------------------------------------------------------------

type Term = { neg: boolean; text: string };
type Op =
  | { k: 'R'; r: number; text: string }
  | { k: 'I'; text: string }
  | { k: 'M'; reg: number; terms: Term[]; inner: string };

// Split the inside of a memory operand into signed terms; empty terms are invalid.
function splitTerms(s: string, bad: () => AsmError): Term[] {
  const terms: Term[] = [];
  let i = 0;
  let neg = false;
  if (s[0] === '+' || s[0] === '-') {
    neg = s[0] === '-';
    i = 1;
  }
  let cur = '';
  const push = () => {
    const t = cur.trim();
    if (t === '') throw bad();
    terms.push({ neg, text: t });
    cur = '';
  };
  while (i < s.length) {
    const c = s[i];
    if (c === "'") {
      const m = CHAR_RE.exec(s.slice(i));
      if (m) {
        cur += m[0];
        i += m[0].length;
        continue;
      }
    }
    if (c === '+' || c === '-') {
      push();
      neg = c === '-';
      i++;
      continue;
    }
    cur += c;
    i++;
  }
  push();
  return terms;
}

function classify(text: string): Op {
  if (text === '') throw asmErr("invalid operand ''");
  const reg = REG_INDEX.get(text);
  if (reg !== undefined) return { k: 'R', r: reg, text };
  if (text.startsWith('[')) {
    const bad = () => asmErr(`invalid operand '${text}'`);
    if (!text.endsWith(']')) throw bad();
    const inner = text.slice(1, -1).trim();
    if (inner === '') throw bad();
    let regIdx = -1;
    const exprs: Term[] = [];
    for (const t of splitTerms(inner, bad)) {
      const r = REG_INDEX.get(t.text);
      if (r !== undefined) {
        if (t.neg || regIdx >= 0) throw bad();
        regIdx = r;
      } else {
        exprs.push(t);
      }
    }
    return { k: 'M', reg: regIdx, terms: exprs, inner };
  }
  return { k: 'I', text };
}

// ---------------------------------------------------------------------------
// Instruction table
// ---------------------------------------------------------------------------

const SPEC = new Map<string, { arity: number; classes: string[] }>();
for (const m of ['add', 'sub', 'mul', 'div', 'mod', 'and', 'or', 'xor', 'shl', 'shr', 'sar', 'cmp']) {
  SPEC.set(m, { arity: 2, classes: ['R', 'RIM'] });
}
SPEC.set('mov', { arity: 2, classes: ['RM', 'RIM'] });
SPEC.set('lea', { arity: 2, classes: ['R', 'M'] });
for (const m of ['neg', 'not', 'inc', 'dec', 'pop', 'in']) SPEC.set(m, { arity: 1, classes: ['R'] });
SPEC.set('push', { arity: 1, classes: ['RIM'] });
for (const m of ['out', 'outc']) SPEC.set(m, { arity: 1, classes: ['RIM'] });
for (const m of ['jmp', 'je', 'jne', 'jz', 'jnz', 'jl', 'jle', 'jg', 'jge', 'call']) {
  SPEC.set(m, { arity: 1, classes: ['I'] });
}
for (const m of ['ret', 'halt', 'nop']) SPEC.set(m, { arity: 0, classes: [] });

const JUMP_TARGETS = new Set(['jmp', 'je', 'jne', 'jz', 'jnz', 'jl', 'jle', 'jg', 'jge', 'call']);

// ---------------------------------------------------------------------------
// Assembler
// ---------------------------------------------------------------------------

type Item =
  | { kind: 'word'; line: number; addr: number; exprs: string[] }
  | { kind: 'space'; line: number; addr: number; n: number; fill: string | null }
  | { kind: 'bytes'; line: number; addr: number; bytes: Buffer }
  | { kind: 'insn'; line: number; mn: string; ops: Op[] };

interface Program {
  code: { line: number; mn: string; ops: Op[] }[];
  items: Item[];
  mem: Int32Array;
  entry: number;
  budget: number;
}

const MEM_WORDS = 4096;

function parseString(s: string): Buffer {
  const bad = () => asmErr('invalid string');
  if (s[0] !== '"') throw bad();
  let out = '';
  let i = 1;
  let closed = false;
  while (i < s.length) {
    const c = s[i];
    if (c === '"') {
      closed = true;
      break;
    }
    if (c === '\\') {
      if (i + 1 >= s.length) throw bad();
      const e = s[i + 1];
      if (!(e in ESC)) throw bad();
      out += String.fromCharCode(ESC[e]);
      i += 2;
      continue;
    }
    out += c;
    i++;
  }
  if (!closed || i !== s.length - 1) throw bad();
  return Buffer.from(out, 'utf8');
}

function assemble(srcLines: string[]): Program {
  let section: 'text' | 'data' = 'text';
  let dataPos = 0;
  let budget = 100000;
  const items: Item[] = [];
  const code: Program['code'] = [];

  const defineLabel = (name: string) => {
    if (REG_INDEX.has(name)) throw asmErr(`reserved name '${name}'`);
    if (symtab.has(name)) throw asmErr(`duplicate symbol '${name}'`);
    symtab.set(name, section === 'text'
      ? { type: 'label', sec: 'text', val: code.length }
      : { type: 'label', sec: 'data', val: dataPos });
  };

  const reserveData = (k: number) => {
    if (dataPos + k > MEM_WORDS) throw asmErr('data section too large');
    const addr = dataPos;
    dataPos += k;
    return addr;
  };

  const directive = (name: string, rest: string) => {
    switch (name) {
      case '.text':
      case '.data':
        if (rest !== '') throw asmErr(`invalid operand '${rest}'`);
        section = name === '.text' ? 'text' : 'data';
        return;
      case '.equ': {
        const ops = splitOperands(rest);
        if (ops.length !== 2) throw asmErr("wrong number of operands for '.equ'");
        const nm = ops[0];
        if (!IDENT_RE.test(nm)) throw asmErr(`invalid operand '${nm}'`);
        if (REG_INDEX.has(nm)) throw asmErr(`reserved name '${nm}'`);
        if (symtab.has(nm)) throw asmErr(`duplicate symbol '${nm}'`);
        symtab.set(nm, { type: 'equ', text: ops[1], state: 0, val: 0 });
        return;
      }
      case '.budget': {
        if (!/^[0-9]+$/.test(rest)) throw asmErr(`invalid operand '${rest}'`);
        const n = Number(rest);
        if (n < 1 || n > 10000000) throw asmErr(`invalid operand '${rest}'`);
        budget = n;
        return;
      }
      case '.word':
      case '.ascii':
      case '.asciz':
      case '.space':
        break;
      default:
        throw asmErr(`unknown directive '${name}'`);
    }
    if (section === 'text') throw asmErr('data directive in text section');
    if (name === '.word') {
      const ops = splitOperands(rest);
      if (ops.length === 0) throw asmErr("wrong number of operands for '.word'");
      const addr = reserveData(ops.length);
      items.push({ kind: 'word', line: curLine, addr, exprs: ops });
    } else if (name === '.ascii' || name === '.asciz') {
      let bytes = parseString(rest);
      if (name === '.asciz') bytes = Buffer.concat([bytes, Buffer.from([0])]);
      const addr = reserveData(bytes.length);
      items.push({ kind: 'bytes', line: curLine, addr, bytes });
    } else {
      const ops = splitOperands(rest);
      if (ops.length < 1 || ops.length > 2) throw asmErr("wrong number of operands for '.space'");
      const n = evalExpr(ops[0]);
      if (n < 0) throw asmErr(`invalid operand '${ops[0]}'`);
      const addr = reserveData(n);
      items.push({ kind: 'space', line: curLine, addr, n, fill: ops.length === 2 ? ops[1] : null });
    }
  };

  const instruction = (s: string) => {
    if (section === 'data') throw asmErr('instruction in data section');
    const m = /^(\S+)\s*(.*)$/.exec(s)!;
    const mn = m[1];
    const rest = m[2].trim();
    const spec = SPEC.get(mn);
    if (!spec) throw asmErr(`unknown mnemonic '${mn}'`);
    const ops = splitOperands(rest).map(classify);
    if (ops.length !== spec.arity) throw asmErr(`wrong number of operands for '${mn}'`);
    ops.forEach((op, idx) => {
      if (!spec.classes[idx].includes(op.k)) throw asmErr(`invalid operands for '${mn}'`);
    });
    if (mn === 'mov' && ops[0].k === 'M' && ops[1].k === 'M') throw asmErr(`invalid operands for '${mn}'`);
    code.push({ line: curLine, mn, ops });
    items.push({ kind: 'insn', line: curLine, mn, ops });
  };

  const pass1Line = (raw: string) => {
    let s = stripComment(raw).trim();
    let m: RegExpExecArray | null;
    while ((m = LABEL_RE.exec(s))) {
      defineLabel(m[1]);
      s = s.slice(m[0].length).trim();
    }
    if (s === '') return;
    if (s[0] === '.') {
      const dm = /^(\S+)\s*(.*)$/.exec(s)!;
      directive(dm[1], dm[2].trim());
    } else {
      instruction(s);
    }
  };

  // Pass 1: labels, directives, instruction shapes, data layout.
  for (let i = 0; i < srcLines.length; i++) {
    curLine = i + 1;
    pass1Line(srcLines[i]);
  }

  // Pass 2: evaluate expressions and validate jump targets, in line order.
  const n = code.length;
  const mem = new Int32Array(MEM_WORDS);
  const evalOp = (op: Op): { k: 'R'; r: number } | { k: 'I'; v: number } | { k: 'M'; reg: number; base: number } => {
    if (op.k === 'R') return { k: 'R', r: op.r };
    if (op.k === 'I') return { k: 'I', v: evalExpr(op.text) };
    let base = 0;
    for (const t of op.terms) {
      const v = evalExpr(t.text, op.inner);
      base = (base + (t.neg ? -v : v)) | 0;
    }
    return { k: 'M', reg: op.reg, base };
  };

  const runtimeCode: { line: number; mn: string; ops: any[] }[] = [];
  for (const it of items) {
    curLine = it.line;
    if (it.kind === 'word') {
      it.exprs.forEach((e, k) => {
        mem[it.addr + k] = evalExpr(e);
      });
    } else if (it.kind === 'space') {
      const fill = it.fill === null ? 0 : evalExpr(it.fill);
      for (let k = 0; k < it.n; k++) mem[it.addr + k] = fill;
    } else if (it.kind === 'bytes') {
      for (let k = 0; k < it.bytes.length; k++) mem[it.addr + k] = it.bytes[k];
    } else {
      const ops = it.ops.map(evalOp);
      if (JUMP_TARGETS.has(it.mn)) {
        const t = (ops[0] as { v: number }).v;
        if (t < 0 || t >= n) throw asmErr('invalid jump target');
      }
      runtimeCode.push({ line: it.line, mn: it.mn, ops });
    }
  }

  const mainSym = symtab.get('main');
  const entry = mainSym && mainSym.type === 'label' && mainSym.sec === 'text' ? mainSym.val : 0;
  return { code: runtimeCode, items, mem, entry, budget };
}

// ---------------------------------------------------------------------------
// Virtual machine
// ---------------------------------------------------------------------------

function execute(prog: Program, input: number[]): string {
  const regs = new Int32Array(10); // r0..r7, sp (8), bp (9)
  regs[8] = 4096;
  let Z = 0;
  let L = 0;
  let pc = prog.entry;
  let steps = 0;
  let inPos = 0;
  let halted = false;
  const outParts: string[] = [];
  const mem = prog.mem;
  const code = prog.code;
  const n = code.length;
  let trapMsg: string | null = null;
  let trapPc = 0;
  let trapLine = '-';

  const memAt = (a: number): number => {
    if (a < 0 || a >= MEM_WORDS) throw new Trap(`memory access out of range: ${a}`);
    return a;
  };
  const ea = (o: any): number => ((o.reg >= 0 ? regs[o.reg] : 0) + o.base) | 0;
  const rd = (o: any): number => (o.k === 'R' ? regs[o.r] : o.k === 'I' ? o.v : mem[memAt(ea(o))]);
  const wr = (o: any, v: number): void => {
    if (o.k === 'R') regs[o.r] = v;
    else mem[memAt(ea(o))] = v;
  };
  const push = (v: number): void => {
    if (regs[8] <= 0) throw new Trap('stack overflow');
    regs[8] = regs[8] - 1;
    mem[memAt(regs[8])] = v;
  };
  const pop = (): number => {
    if (regs[8] >= MEM_WORDS) throw new Trap('stack underflow');
    const v = mem[memAt(regs[8])];
    regs[8] = regs[8] + 1;
    return v;
  };

  try {
    for (;;) {
      if (pc < 0 || pc >= n) {
        trapMsg = 'pc out of range';
        trapPc = pc;
        trapLine = '-';
        break;
      }
      const ins = code[pc];
      if (steps === prog.budget) {
        trapMsg = 'budget exceeded';
        trapPc = pc;
        trapLine = String(ins.line);
        break;
      }
      const o = ins.ops;
      let next = pc + 1;
      switch (ins.mn) {
        case 'mov':
          wr(o[0], rd(o[1]));
          break;
        case 'add': case 'sub': case 'mul': case 'div': case 'mod':
        case 'and': case 'or': case 'xor': case 'shl': case 'shr': case 'sar': {
          const b = rd(o[1]);
          const d = o[0].r;
          const a = regs[d];
          let r: number;
          switch (ins.mn) {
            case 'add': r = a + b; break;
            case 'sub': r = a - b; break;
            case 'mul': r = Math.imul(a, b); break;
            case 'div':
              if (b === 0) throw new Trap('division by zero');
              r = (a / b) | 0;
              break;
            case 'mod':
              if (b === 0) throw new Trap('division by zero');
              r = (a % b) | 0;
              break;
            case 'and': r = a & b; break;
            case 'or': r = a | b; break;
            case 'xor': r = a ^ b; break;
            case 'shl': r = a << (b & 31); break;
            case 'shr': r = a >>> (b & 31); break;
            default: r = a >> (b & 31); break; // sar
          }
          regs[d] = r;
          break;
        }
        case 'cmp': {
          const b = rd(o[1]);
          const a = regs[o[0].r];
          Z = a === b ? 1 : 0;
          L = a < b ? 1 : 0;
          break;
        }
        case 'neg': regs[o[0].r] = -regs[o[0].r]; break;
        case 'not': regs[o[0].r] = ~regs[o[0].r]; break;
        case 'inc': regs[o[0].r] = regs[o[0].r] + 1; break;
        case 'dec': regs[o[0].r] = regs[o[0].r] - 1; break;
        case 'lea':
          regs[o[0].r] = ea(o[1]);
          break;
        case 'push':
          push(rd(o[0]));
          break;
        case 'pop': {
          const v = pop();
          regs[o[0].r] = v;
          break;
        }
        case 'call':
          push(next);
          next = o[0].v;
          break;
        case 'ret':
          next = pop();
          break;
        case 'jmp': next = o[0].v; break;
        case 'je': case 'jz': if (Z === 1) next = o[0].v; break;
        case 'jne': case 'jnz': if (Z === 0) next = o[0].v; break;
        case 'jl': if (L === 1) next = o[0].v; break;
        case 'jle': if (L === 1 || Z === 1) next = o[0].v; break;
        case 'jg': if (L === 0 && Z === 0) next = o[0].v; break;
        case 'jge': if (L === 0) next = o[0].v; break;
        case 'in':
          if (inPos >= input.length) throw new Trap('input exhausted');
          regs[o[0].r] = input[inPos++];
          break;
        case 'out':
          outParts.push(`${rd(o[0])}\n`);
          break;
        case 'outc': {
          const v = rd(o[0]);
          if (v < 0 || v > 127) throw new Trap('invalid character');
          outParts.push(String.fromCharCode(v));
          break;
        }
        case 'halt':
          halted = true;
          break;
        case 'nop':
          break;
        default:
          throw new Error(`internal: unknown instruction ${ins.mn}`);
      }
      steps++;
      if (halted) break;
      pc = next;
    }
  } catch (e) {
    if (!(e instanceof Trap)) throw e;
    trapMsg = e.message;
    trapPc = pc;
    trapLine = String(code[pc].line);
  }

  let text = outParts.join('');
  if (text.length > 0 && !text.endsWith('\n')) text += '\n';
  if (trapMsg !== null) {
    text += `-- trap: ${trapMsg} (pc=${trapPc} line=${trapLine}) after ${steps} steps\n`;
  } else {
    text += `-- halted after ${steps} steps\n`;
  }
  const names = ['r0', 'r1', 'r2', 'r3', 'r4', 'r5', 'r6', 'r7'];
  text += `regs: ${names.map((nm, i) => `${nm}=${regs[i]}`).join(' ')} sp=${regs[8]} bp=${regs[9]}\n`;
  text += `flags: Z=${Z} L=${L}\n`;
  return text;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

function main(): void {
  const input = readFileSync(0, 'utf8');
  const lines = input.split(/\r?\n/);
  const sep = lines.indexOf('====');
  const srcLines = sep >= 0 ? lines.slice(0, sep) : lines;
  const inputNums: number[] = [];
  if (sep >= 0) {
    for (const tok of lines.slice(sep + 1).join(' ').split(/\s+/)) {
      if (/^-?[0-9]+$/.test(tok)) inputNums.push(Number(BigInt.asIntN(32, BigInt(tok))));
    }
  }

  let out: string;
  try {
    const prog = assemble(srcLines);
    out = execute(prog, inputNums);
  } catch (e) {
    if (e instanceof AsmError) out = `asm error line ${curLine}: ${e.message}\n`;
    else throw e;
  }
  process.stdout.write(out);
}

main();
