// Manuscript Runtime Library

import { getCompiledStdlib } from "../stdlib/compiled";

// Context base type - factory function returning null-prototype object
// Used as embedded marker in capability types
const Context$methods = Object.assign(Object.create(null), {
  close() {}
});

export function Context() {
  return Object.create(Context$methods);
}

// Context stack for ambient context
const __contextStack: Map<string, any>[] = [];

export function __pushContext(): void {
  __contextStack.push(new Map());
}

export function __popContext(): void {
  __contextStack.pop();
}

export function __setContext(typeName: string, value: any): void {
  const current = __contextStack[__contextStack.length - 1];
  if (current) current.set(typeName, value);
}

export function __getContext(typeName: string): any {
  for (let i = __contextStack.length - 1; i >= 0; i--) {
    const scope = __contextStack[i];
    if (scope?.has(typeName)) return scope.get(typeName);
  }
  throw new Error(`No context of type '${typeName}' available. Use 'with' to provide it.`);
}

// Re-export modules
export { Agent } from "./agent";
export { Channel, spawn, sleep, all_settled, race, timeout, delay } from "./concurrency";
export { test, getTestCount, clearTests, runTests, runTestsWithResults } from "./testing";

import { Agent } from "./agent";
import { Channel, spawn, sleep, all_settled, race, timeout, delay } from "./concurrency";
import { test, getTestCount, clearTests, runTests, runTestsWithResults } from "./testing";

// ============================================
// Extern functions (require JS APIs)
// ============================================

function print(...args: any[]): void { console.log(...args); }
function log(...args: any[]): void { console.log(...args); }
function now(): number { return Date.now(); }

function typeOf(x: any): string {
  if (x === null) return "null";
  if (Array.isArray(x)) return "list";
  if (x instanceof Map) return "map";
  if (x instanceof Set) return "set";
  if (x instanceof Channel) return "channel";
  if (typeof x === "object" && x.__typename) {
    return x.__typename;
  }
  if (typeof x === "object" && x.constructor && x.constructor.name !== "Object") {
    return x.constructor.name;
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

function hash(x: any): number {
  const str = JSON.stringify(x);
  let h = 0;
  for (let i = 0; i < str.length; i++) {
    h = ((h << 5) - h) + str.charCodeAt(i);
    h |= 0;
  }
  return h;
}

function to_str(x: any): string {
  if (x === null) return "null";
  if (typeof x === "object") {
    // For Manuscript types with __typename, use the type name
    if (x.__typename) return x.__typename;
    return JSON.stringify(x);
  }
  return String(x);
}
function to_num(s: string): number { return Number(s); }
function to_json(x: any): string { return JSON.stringify(x); }
function from_json(s: string): any { return JSON.parse(s); }

function len(x: any): number {
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
function template(_name: string, parts: any[]): string {
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

// ============================================
// Runtime object
// ============================================

export const __ms_runtime: Record<string, any> = {
  // Classes
  Context, Agent, Channel,
  
  // Context stack
  __pushContext, __popContext, __setContext, __getContext,
  
  // Test runner
  test, getTestCount, clearTests, runTests, runTestsWithResults,
  
  // Concurrency
  spawn, sleep, all_settled, race, timeout, delay,
  
  // Internal (codegen)
  range, template,
  
  // Extern functions
  print, log, now,
  typeof: typeOf, clone, hash,
  to_str, to_num, to_json, from_json,
  len, keys, values, entries, sort,
  upper, lower, trim, split, join, replace, starts_with, ends_with, substring, matches,
  sqrt, pow, floor, ceil, round, random, random_int,
  panic, error,
  set: setFromList, union: setUnion, intersect: setIntersect, difference: setDifference, is_subset: setIsSubset,
};

// Add compiled stdlib (types and pure functions from stdlib.ms)
Object.assign(__ms_runtime, getCompiledStdlib(__ms_runtime));
