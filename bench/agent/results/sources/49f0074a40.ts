// Read stdin, write stdout. See TASK.md.
import { readFileSync } from 'node:fs';

function mod26(n: number): number {
  return ((n % 26) + 26) % 26;
}

// Shift one character: letters rotate within their case, everything else is unchanged.
function shiftChar(c: string, s: number): string {
  const code = c.charCodeAt(0);
  if (code >= 65 && code <= 90) {
    return String.fromCharCode(((code - 65 + s) % 26 + 26) % 26 + 65);
  }
  if (code >= 97 && code <= 122) {
    return String.fromCharCode(((code - 97 + s) % 26 + 26) % 26 + 97);
  }
  return c;
}

function processLine(line: string): string {
  const i1 = line.indexOf(' ');
  const i2 = i1 < 0 ? -1 : line.indexOf(' ', i1 + 1);
  const i3 = i2 < 0 ? -1 : line.indexOf(' ', i2 + 1);
  if (i3 < 0 || i3 + 1 >= line.length) {
    return 'error: bad command';
  }
  const cipher = line.slice(0, i1);
  const mode = line.slice(i1 + 1, i2);
  const key = line.slice(i2 + 1, i3);
  const text = line.slice(i3 + 1);

  if (cipher !== 'caesar' && cipher !== 'vigenere') {
    return 'error: bad cipher';
  }
  if (mode !== 'enc' && mode !== 'dec') {
    return 'error: bad mode';
  }
  const sign = mode === 'enc' ? 1 : -1;

  if (cipher === 'caesar') {
    if (!/^-?\d{1,7}$/.test(key)) {
      return 'error: bad key';
    }
    const shift = mod26(sign * parseInt(key, 10));
    let out = '';
    for (const c of text) out += shiftChar(c, shift);
    return out;
  }

  // vigenere
  if (!/^[A-Za-z]+$/.test(key)) {
    return 'error: bad key';
  }
  const shifts = Array.from(key.toLowerCase(), (k) => k.charCodeAt(0) - 97);
  let out = '';
  let pos = 0;
  for (const c of text) {
    if (/[A-Za-z]/.test(c)) {
      out += shiftChar(c, sign * shifts[pos % shifts.length]);
      pos++;
    } else {
      out += c;
    }
  }
  return out;
}

const input = readFileSync(0, 'utf8');
const lines = input.split('\n');
const results: string[] = [];
for (let line of lines) {
  if (line.endsWith('\r')) line = line.slice(0, -1);
  if (/^ *$/.test(line)) continue; // blank lines produce no output
  results.push(processLine(line));
}
if (results.length > 0) {
  process.stdout.write(results.join('\n') + '\n');
}
