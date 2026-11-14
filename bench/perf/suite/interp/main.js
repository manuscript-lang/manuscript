const [PUSH, LOAD, STORE, ADD, MUL, MOD, LT, JZ, JMP, HALT] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];

function program(n, m) {
  const P = (k, a = 0) => ({ kind: k, arg: a });
  return [
    P(PUSH, 0), P(STORE, 0),
    P(PUSH, 0), P(STORE, 1),
    P(LOAD, 1), P(PUSH, n), P(LT), P(JZ, 33),
    P(PUSH, 0), P(STORE, 2),
    P(LOAD, 2), P(PUSH, m), P(LT), P(JZ, 28),
    P(LOAD, 0), P(LOAD, 1), P(LOAD, 2), P(MUL), P(PUSH, 7), P(MOD), P(ADD), P(STORE, 0),
    P(LOAD, 2), P(PUSH, 1), P(ADD), P(STORE, 2),
    P(JMP, 10), P(HALT),
    P(LOAD, 1), P(PUSH, 1), P(ADD), P(STORE, 1), P(JMP, 4),
    P(HALT),
  ];
}

function run(code) {
  const stack = [];
  const vars = [0, 0, 0, 0];
  let pc = 0, steps = 0;
  for (;;) {
    steps++;
    const op = code[pc];
    switch (op.kind) {
      case PUSH: stack.push(op.arg); pc++; break;
      case LOAD: stack.push(vars[op.arg]); pc++; break;
      case STORE: vars[op.arg] = stack.pop(); pc++; break;
      case ADD: { const b = stack.pop(), a = stack.pop(); stack.push(a + b); pc++; break; }
      case MUL: { const b = stack.pop(), a = stack.pop(); stack.push(a * b); pc++; break; }
      case MOD: { const b = stack.pop(), a = stack.pop(); stack.push(a % b); pc++; break; }
      case LT: { const b = stack.pop(), a = stack.pop(); stack.push(a < b ? 1 : 0); pc++; break; }
      case JZ: pc = stack.pop() === 0 ? op.arg : pc + 1; break;
      case JMP: pc = op.arg; break;
      case HALT: console.log(`steps ${steps}`); return vars[0];
    }
  }
}

console.log(`total ${run(program(3000, 2000))}`);
