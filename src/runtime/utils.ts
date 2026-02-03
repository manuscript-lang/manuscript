// Utility Functions

import { Channel } from "./concurrency";

export function print(...args: any[]): void {
  console.log(...args);
}

export function log(...args: any[]): void {
  console.log(...args);
}

export function now(): number {
  return Date.now();
}

export function typeOf(x: any): string {
  if (x === null) return "null";
  if (Array.isArray(x)) return "list";
  if (x instanceof Map) return "map";
  if (x instanceof Set) return "set";
  if (x instanceof Channel) return "channel";
  if (typeof x === "object" && x.constructor && x.constructor.name !== "Object") {
    return x.constructor.name;
  }
  return typeof x;
}

export function clone<T>(x: T): T {
  if (x === null || typeof x !== "object") return x;
  if (Array.isArray(x)) return [...x] as T;
  if (x instanceof Map) return new Map(x) as T;
  if (x instanceof Set) return new Set(x) as T;
  return { ...x };
}

export function equals(a: any, b: any): boolean {
  if (a === b) return true;
  if (typeof a !== typeof b) return false;
  if (typeof a !== "object" || a === null) return false;
  
  if (Array.isArray(a) && Array.isArray(b)) {
    if (a.length !== b.length) return false;
    return a.every((v, i) => equals(v, b[i]));
  }
  
  const keysA = Object.keys(a);
  const keysB = Object.keys(b);
  if (keysA.length !== keysB.length) return false;
  
  return keysA.every((key) => equals(a[key], b[key]));
}

export function hash(x: any): number {
  const str = JSON.stringify(x);
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    hash = ((hash << 5) - hash) + str.charCodeAt(i);
    hash |= 0;
  }
  return hash;
}

// Conversion
export function to_str(x: any): string {
  if (x === null) return "null";
  if (typeof x === "object") return JSON.stringify(x);
  return String(x);
}

export function to_num(s: string): number {
  return Number(s);
}

export function to_json(x: any): string {
  return JSON.stringify(x);
}

export function from_json(s: string): any {
  return JSON.parse(s);
}

// Sets
export function set<T>(list: T[]): Set<T> {
  return new Set(list);
}

export function union<T>(a: Set<T>, b: Set<T>): Set<T> {
  return new Set([...a, ...b]);
}

export function intersect<T>(a: Set<T>, b: Set<T>): Set<T> {
  return new Set([...a].filter((x) => b.has(x)));
}

export function difference<T>(a: Set<T>, b: Set<T>): Set<T> {
  return new Set([...a].filter((x) => !b.has(x)));
}

export function is_subset<T>(a: Set<T>, b: Set<T>): boolean {
  return [...a].every((x) => b.has(x));
}

// Assert
export function assert(value: any, message?: string): void {
  if (!value) throw new Error(message || "Assertion failed");
}

// Errors
export function error(message: string, cause?: Error): Error {
  const err = new Error(message);
  if (cause) err.cause = cause;
  return err;
}

export function ok<T>(value: T): { ok: true; value: T } {
  return { ok: true, value };
}

export function err<E>(error: E): { ok: false; error: E } {
  return { ok: false, error };
}

// Range and template
export function range(start: number, end: number, inclusive: boolean = false): number[] {
  const result: number[] = [];
  const stop = inclusive ? end + 1 : end;
  for (let i = start; i < stop; i++) result.push(i);
  return result;
}

export function template(name: string, parts: any[]): string {
  return parts.map(p => String(p)).join("");
}
