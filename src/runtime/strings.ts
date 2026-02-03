// String Functions

export function upper(s: string): string {
  return s.toUpperCase();
}

export function lower(s: string): string {
  return s.toLowerCase();
}

export function trim(s: string): string {
  return s.trim();
}

export function split(s: string, delim: string): string[] {
  return s.split(delim);
}

export function join(list: string[], delim: string): string {
  return list.join(delim);
}

export function replace(s: string, old: string, newStr: string): string {
  return s.replaceAll(old, newStr);
}

export function starts_with(s: string, prefix: string): boolean {
  return s.startsWith(prefix);
}

export function ends_with(s: string, suffix: string): boolean {
  return s.endsWith(suffix);
}

export function substring(s: string, start: number, end?: number): string {
  return s.substring(start, end);
}

export function matches(s: string, pattern: string): boolean {
  return new RegExp(pattern).test(s);
}
