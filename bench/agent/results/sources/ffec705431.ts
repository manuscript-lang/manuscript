// Read stdin, write stdout. See TASK.md.
import readFileSync from 'node:fs';

const CAESAR_KEY = /^-?[0-9]{1,7}$/;
const VIGENERE_KEY = /^[A-Za-z]+$/;

// Shift one letter by `amount` positions, keeping its case. Non-letters are returned unchanged.
function shiftLetter(ch: string, amount: number): string {
  const code = ch.charCodeAt(0);
  const base = code >= 65 && code <= 90 ? 65 : code >= 97 && code <= 122 ? 97 : -1;
  if (base < 0) return ch;
  const offset = (((code - base + amount) % 26) + 26) % 26;
  return String.fromCharCode(base + offset);
}

function caesar(mode: string, key: string, text: string): string {
  const shift = Number(key) * (mode === 'enc' ? 1 : -1);
  let out = '';
  for (const ch of text) out += shiftLetter(ch, shift);
  return out;
}

function vigenere(mode: string, key: string, text: string): string {
  const shifts = [...key].map((ch) => ch.toUpperCase().charCodeAt(0) - 65);
  const sign = mode === 'enc' ? 1 : -1;
  let out = '';
  let pos = 0;
  for (const ch of text) {
    if (/[A-Za-z]/.test(ch)) {
      out += shiftLetter(ch, sign * shifts[pos % shifts.length]);
      pos++;
    } else {
      out += ch;
    }
  }
  return out;
}

function runLine(line: string): string {
  const first = line.indexOf(' ');
  const second = first < 0 ? -1 : line.indexOf(' ', first + 1);
  const third = second < 0 ? -1 : line.indexOf(' ', second + 1);
  if (third < 0 || third === line.length - 1) return 'error: bad command';

  const cipher = line.slice(0, first);
  const mode = line.slice(first + 1, second);
  const key = line.slice(second + 1, third);
  const text = line.slice(third + 1);

  if (cipher !== 'caesar' && cipher !== 'vigenere') return 'error: bad cipher';
  if (mode !== 'enc' && mode !== 'dec') return 'error: bad mode';

  if (cipher === 'caesar') {
    if (!CAESAR_KEY.test(key)) return 'error: bad key';
    return caesar(mode, key, text);
  }
  if (!VIGENERE_KEY.test(key)) return 'error: bad key';
  return vigenere(mode, key, text);
}

const lines = readFileSync(0, 'utf8').split('\n');
const out: string[] = [];
for (const raw of lines) {
  if (/^ *$/.test(raw)) continue;
  out.push(runLine(raw));
}
process.stdout.write(out.map((l) => l + '\n').join(''));
