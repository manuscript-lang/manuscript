// Manuscript Runtime Library

import { getCompiledBuiltins } from "../builtin/compiled";

// Context base type - factory function returning null-prototype object
// Used as embedded marker in capability types
const Context$methods = Object.assign(Object.create(null), {
  close() {}
});

export function Context() {
  return Object.create(Context$methods);
}

// Context stack for ambient context
const __contextStack: Map<string, unknown>[] = [];

export function __pushContext(): void {
  __contextStack.push(new Map());
}

export function __popContext(): void {
  __contextStack.pop();
}

export function __setContext(typeName: string, value: unknown): void {
  const current = __contextStack[__contextStack.length - 1];
  if (current) current.set(typeName, value);
}

export function __getContext(typeName: string): unknown {
  for (let i = __contextStack.length - 1; i >= 0; i--) {
    const scope = __contextStack[i];
    if (scope?.has(typeName)) return scope.get(typeName);
  }
  throw new Error(`No context of type '${typeName}' available. Use 'with' to provide it.`);
}

// Re-export modules
export { spawn, sleep, all_settled, race, resolve, timeout, delay } from "./concurrency";
export { test, getTestCount, clearTests, runTests, runTestsWithResults } from "./testing";

import { spawn, sleep, all_settled, race, resolve, timeout, delay } from "./concurrency";
import { test, getTestCount, clearTests, runTests, runTestsWithResults } from "./testing";

// ============================================
// Extern functions (require JS APIs)
// ============================================

function print(...args: unknown[]): void { console.log(...args); }
function log(...args: unknown[]): void { console.log(...args); }
function now(): number { return Date.now(); }

function typeOf(x: unknown): string {
  if (x === null) return "null";
  if (Array.isArray(x)) return "list";
  if (x instanceof Map) return "map";
  if (x instanceof Set) return "set";
  if (typeof x === "object" && x !== null && "__typename" in x && typeof (x as { __typename: string }).__typename === "string") {
    return (x as { __typename: string }).__typename;
  }
  if (typeof x === "object" && x !== null && "constructor" in x && (x as { constructor: { name: string } }).constructor?.name !== "Object") {
    return (x as { constructor: { name: string } }).constructor.name;
  }
  return typeof x;
}

function clone<T>(x: T): T {
  if (x === null || typeof x !== "object") return x;
  if (Array.isArray(x)) return [...x] as T;
  if (x instanceof Map) return new Map(x) as T;
  if (x instanceof Set) return new Set(x) as T;
  return { ...x };
}

function hash(x: unknown): number {
  const str = JSON.stringify(x);
  let h = 0;
  for (let i = 0; i < str.length; i++) {
    h = ((h << 5) - h) + str.charCodeAt(i);
    h |= 0;
  }
  return h;
}

function to_str(x: unknown): string {
  if (x === null) return "null";
  if (typeof x === "object" && x !== null) {
    if ("__typename" in x && typeof (x as { __typename: string }).__typename === "string") return (x as { __typename: string }).__typename;
    return JSON.stringify(x);
  }
  return String(x);
}
function to_num(s: string): number { return Number(s); }
function getenv(name: string): string {
  if (typeof process !== "undefined" && process.env && typeof process.env[name] === "string") return process.env[name]!;
  return "";
}

function stripForJson(x: unknown): unknown {
  if (x === null || typeof x !== "object") return x;
  if (Array.isArray(x)) return x.map(stripForJson);
  if (x instanceof Map || x instanceof Set) return x;
  const o = x as Record<string, unknown>;
  const out: Record<string, unknown> = {};
  for (const k of Object.keys(o)) {
    if (k === "__typename" || k === "__typeArgs") continue;
    out[k] = stripForJson(o[k]);
  }
  return out;
}

function to_json(x: unknown): string {
  return JSON.stringify(stripForJson(x));
}

function from_json(s: string): unknown { return JSON.parse(s); }

function len(x: unknown): number {
  if (typeof x === "string" || Array.isArray(x)) return x.length;
  if (x instanceof Map || x instanceof Set) return x.size;
  if (typeof x === "object" && x !== null) return Object.keys(x).length;
  return 0;
}
function keys<K, V>(map: Map<K, V> | Record<string, V>): K[] {
  if (map instanceof Map) return Array.from(map.keys());
  return Object.keys(map) as K[];
}
function values<K, V>(map: Map<K, V> | Record<string, V>): V[] {
  if (map instanceof Map) return Array.from(map.values());
  return Object.values(map);
}
function entries<K, V>(map: Map<K, V> | Record<string, V>): [K, V][] {
  if (map instanceof Map) return Array.from(map.entries());
  return Object.entries(map) as [K, V][];
}
function sort<T>(list: T[]): T[] { return [...list].sort(); }

function upper(s: string): string { return s.toUpperCase(); }
function lower(s: string): string { return s.toLowerCase(); }
function trim(s: string): string { return s.trim(); }
function split(s: string, delim: string): string[] { return s.split(delim); }
function join(list: string[], delim: string): string { return list.join(delim); }
function replace(s: string, old: string, replacement: string): string { return s.replaceAll(old, replacement); }
function starts_with(s: string, prefix: string): boolean { return s.startsWith(prefix); }
function ends_with(s: string, suffix: string): boolean { return s.endsWith(suffix); }
function substring(s: string, start: number, end?: number): string { return s.substring(start, end); }
function matches(s: string, pattern: string): boolean { return new RegExp(pattern).test(s); }

const sqrt = Math.sqrt;
const pow = Math.pow;
const floor = Math.floor;
const ceil = Math.ceil;
const round = Math.round;
function random(): number { return Math.random(); }
function random_int(minVal: number, maxVal: number): number {
  return Math.floor(Math.random() * (maxVal - minVal + 1)) + minVal;
}

function panic(message: string): never { throw new Error(message); }
function error(message: string, cause?: Error): Error {
  const err = new Error(message);
  if (cause) err.cause = cause;
  return err;
}

function range(start: number, end: number, inclusive: boolean = false): number[] {
  const result: number[] = [];
  const stop = inclusive ? end + 1 : end;
  for (let i = start; i < stop; i++) result.push(i);
  return result;
}
function template(_name: string, parts: unknown[]): string {
  return parts.map(p => String(p)).join("");
}

function setFromList<T>(list: T[]): Set<T> {
  return new Set(list);
}
function setUnion<T>(a: Set<T>, b: Set<T>): Set<T> {
  return new Set([...a, ...b]);
}
function setIntersect<T>(a: Set<T>, b: Set<T>): Set<T> {
  return new Set([...a].filter(x => b.has(x)));
}
function setDifference<T>(a: Set<T>, b: Set<T>): Set<T> {
  return new Set([...a].filter(x => !b.has(x)));
}
function setIsSubset<T>(a: Set<T>, b: Set<T>): boolean {
  return [...a].every(x => b.has(x));
}

async function fetchImpl(
  url: string,
  options?: { method?: string; body?: string; headers?: Map<string, string> | Record<string, string> }
): Promise<{ status: number; body: string }> {
  const method = options?.method ?? "GET";
  const body = options?.body ?? undefined;
  const headers = options?.headers;
  const init: RequestInit = { method, body };
  if (headers) {
    init.headers = headers instanceof Map
      ? Object.fromEntries(headers)
      : (headers as Record<string, string>);
  }
  const res = await globalThis.fetch(url, init);
  const text = await res.text();
  return { status: res.status, body: text };
}

async function fetchStreamImpl(
  url: string,
  options?: { method?: string; body?: string; headers?: Map<string, string> | Record<string, string> }
): Promise<{ status: number; body: AsyncIterable<string> }> {
  const method = options?.method ?? "GET";
  const body = options?.body ?? undefined;
  const headers = options?.headers;
  const init: RequestInit = { method, body };
  if (headers) {
    init.headers = headers instanceof Map
      ? Object.fromEntries(headers)
      : (headers as Record<string, string>);
  }
  const res = await globalThis.fetch(url, init);
  if (!res.body) {
    return { status: res.status, body: (async function* () {})() };
  }
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  const bodyStream = {
    async *[Symbol.asyncIterator]() {
      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) return;
          if (value) yield decoder.decode(value);
        }
      } finally {
        reader.releaseLock();
      }
    },
  };
  return { status: res.status, body: bodyStream };
}

// ============================================
// Runtime object (typed view for callers)
// ============================================

export interface ManuscriptRuntime {
  Context: () => object;
  __pushContext: () => void;
  __popContext: () => void;
  __setContext: (typeName: string, value: unknown) => void;
  __getContext: (typeName: string) => unknown;
  test: (name: string, fn: () => void | Promise<void>) => void;
  getTestCount: () => number;
  clearTests: () => void;
  runTests: () => void;
  runTestsWithResults: () => Promise<{ name: string; passed: boolean; error?: string }[]>;
  spawn: (fn: () => Promise<unknown>) => Promise<unknown>;
  sleep: (ms: number) => Promise<void>;
  all_settled: (promises: Promise<unknown>[]) => Promise<unknown[]>;
  race: (promises: Promise<unknown>[]) => Promise<unknown>;
  resolve: <T>(value: T) => Promise<T>;
  timeout: <T>(p: Promise<T>, ms: number) => Promise<T>;
  delay: (ms: number) => Promise<void>;
  range: (start: number, end: number, inclusive?: boolean) => number[];
  template: (_name: string, parts: unknown[]) => string;
  print: (...args: unknown[]) => void;
  log: (...args: unknown[]) => void;
  now: () => number;
  typeof: (x: unknown) => string;
  clone: <T>(x: T) => T;
  hash: (x: unknown) => number;
  to_str: (x: unknown) => string;
  to_num: (s: string) => number;
  getenv: (name: string) => string;
  to_json: (x: unknown) => string;
  from_json: (s: string) => unknown;
  len: (x: unknown) => number;
  keys: <K, V>(map: Map<K, V> | Record<string, V>) => K[];
  values: <K, V>(map: Map<K, V> | Record<string, V>) => V[];
  entries: <K, V>(map: Map<K, V> | Record<string, V>) => [K, V][];
  sort: <T>(list: T[]) => T[];
  upper: (s: string) => string;
  lower: (s: string) => string;
  trim: (s: string) => string;
  split: (s: string, delim: string) => string[];
  join: (list: string[], delim: string) => string;
  replace: (s: string, old: string, replacement: string) => string;
  starts_with: (s: string, prefix: string) => boolean;
  ends_with: (s: string, suffix: string) => boolean;
  substring: (s: string, start: number, end?: number) => string;
  matches: (s: string, pattern: string) => boolean;
  sqrt: (x: number) => number;
  pow: (x: number, y: number) => number;
  floor: (x: number) => number;
  ceil: (x: number) => number;
  round: (x: number) => number;
  random: () => number;
  random_int: (minVal: number, maxVal: number) => number;
  panic: (message: string) => never;
  error: (message: string, cause?: Error) => Error;
  set: <T>(list: T[]) => Set<T>;
  union: <T>(a: Set<T>, b: Set<T>) => Set<T>;
  intersect: <T>(a: Set<T>, b: Set<T>) => Set<T>;
  difference: <T>(a: Set<T>, b: Set<T>) => Set<T>;
  is_subset: <T>(a: Set<T>, b: Set<T>) => boolean;
  fetch: (url: string, options?: { method?: string; body?: string; headers?: Map<string, string> | Record<string, string> }) => Promise<{ status: number; body: string }>;
  fetch_stream: (url: string, options?: { method?: string; body?: string; headers?: Map<string, string> | Record<string, string> }) => Promise<{ status: number; body: AsyncIterable<string> }>;
  abs: (x: number) => number | Promise<number>;
  min: (...args: number[]) => number | Promise<number>;
  max: (...args: number[]) => number | Promise<number>;
  clamp: (v: number, lo: number, hi: number) => number | Promise<number>;
  first: <T>(list: T[]) => T | Promise<T>;
  last: <T>(list: T[]) => T | Promise<T>;
  take: <T>(list: T[], n: number) => T[] | Promise<T[]>;
  drop: <T>(list: T[], n: number) => T[] | Promise<T[]>;
  reverse: <T>(list: T[]) => T[] | Promise<T[]>;
  contains: <T>(list: T[], x: T) => boolean | Promise<boolean>;
  unique: <T>(list: T[]) => T[] | Promise<T[]>;
  flatten: <T>(list: T[][]) => T[] | Promise<T[]>;
  zip: <A, B>(a: A[], b: B[]) => [A, B][] | Promise<[A, B][]>;
  concat: <T>(...lists: T[][]) => T[] | Promise<T[]>;
  slice: <T>(list: T[], start: number, end?: number) => T[] | Promise<T[]>;
  map: <T, U>(list: T[], fn: (x: T) => U) => U[] | Promise<U[]>;
  filter: <T>(list: T[], fn: (x: T) => boolean) => T[] | Promise<T[]>;
  reduce: <T, U>(list: T[], init: U, fn: (a: U, x: T) => U) => U | Promise<U>;
  find: <T>(list: T[], fn: (x: T) => boolean) => T | undefined | Promise<T | undefined>;
  any: <T>(list: T[], fn: (x: T) => boolean) => boolean | Promise<boolean>;
  all: <T>(list: T[], fn: (x: T) => boolean) => boolean | Promise<boolean>;
  ok: <T>(value: T) => unknown | Promise<unknown>;
  err: (message: string) => unknown | Promise<unknown>;
  equals: (a: unknown, b: unknown) => boolean | Promise<boolean>;
  [key: string]: unknown;
}

const __ms_runtime_impl: Record<string, unknown> = {
  // Classes
  Context,

  // Context stack
  __pushContext, __popContext, __setContext, __getContext,
  
  // Test runner
  test, getTestCount, clearTests, runTests, runTestsWithResults,
  
  // Concurrency
  spawn, sleep, all_settled, race, resolve, timeout, delay,
  
  // Internal (codegen)
  range, template,
  
  // Extern functions
  print, log, now,
  typeof: typeOf, clone, hash,
  to_str, to_num, getenv, to_json, from_json,
  len, keys, values, entries, sort,
  upper, lower, trim, split, join, replace, starts_with, ends_with, substring, matches,
  sqrt, pow, floor, ceil, round, random, random_int,
  panic, error,
  set: setFromList, union: setUnion, intersect: setIntersect, difference: setDifference, is_subset: setIsSubset,
  fetch: fetchImpl,
  fetch_stream: fetchStreamImpl,
};

// Add compiled pure functions from builtins.ms and stdlib modules
Object.assign(__ms_runtime_impl, getCompiledBuiltins(__ms_runtime_impl));

export const __ms_runtime: ManuscriptRuntime = __ms_runtime_impl as ManuscriptRuntime;
