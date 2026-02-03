// Manuscript Runtime Library
// Context is available via a runtime stack, pushed by `with` blocks.

// Context base class for all capability/context types
export class Context {
  // Called automatically when exiting a `with` block
  exit(): void {}
}

// Context stack for ambient context (non-viral using)
const __contextStack: Map<string, any>[] = [];

export function __pushContext(): void {
  __contextStack.push(new Map());
}

export function __popContext(): void {
  __contextStack.pop();
}

export function __setContext(typeName: string, value: any): void {
  const current = __contextStack[__contextStack.length - 1];
  if (current) {
    current.set(typeName, value);
  }
}

export function __getContext(typeName: string): any {
  // Search from innermost to outermost scope
  for (let i = __contextStack.length - 1; i >= 0; i--) {
    const scope = __contextStack[i];
    if (scope?.has(typeName)) {
      return scope.get(typeName);
    }
  }
  throw new Error(`No context of type '${typeName}' available. Use 'with' to provide it.`);
}

// Re-export all modules
export { Agent } from "./agent";
export { Channel, spawn, sleep, all_settled, race, timeout, delay } from "./concurrency";
export { test, getTestCount, clearTests, runTests, runTestsWithResults } from "./testing";
export * from "./collections";
export * from "./strings";
export * from "./numbers";
export * from "./utils";

// Import for __ms_runtime object
import { Agent } from "./agent";
import { Channel, spawn, sleep, all_settled, race, timeout, delay } from "./concurrency";
import { test, getTestCount, clearTests, runTests, runTestsWithResults } from "./testing";
import * as collections from "./collections";
import * as strings from "./strings";
import * as numbers from "./numbers";
import * as utils from "./utils";

// Runtime object for compiled code
export const __ms_runtime = {
  // Classes
  Context,
  Agent,
  Channel,
  
  // Context stack (for non-viral using)
  __pushContext,
  __popContext,
  __setContext,
  __getContext,
  
  // Test runner
  test,
  getTestCount,
  clearTests,
  runTests,
  runTestsWithResults,
  
  // Utilities
  spawn,
  range: utils.range,
  template: utils.template,
  
  // Collections
  len: collections.len,
  keys: collections.keys,
  values: collections.values,
  entries: collections.entries,
  contains: collections.contains,
  unique: collections.unique,
  flatten: collections.flatten,
  sort: collections.sort,
  reverse: collections.reverse,
  first: collections.first,
  last: collections.last,
  take: collections.take,
  drop: collections.drop,
  zip: collections.zip,
  map: collections.map,
  each: collections.each,
  filter: collections.filter,
  slice: collections.slice,
  concat: collections.concat,
  reduce: collections.reduce,
  find: collections.find,
  any: collections.any,
  all: collections.all,
  group_by: collections.group_by,
  sort_by: collections.sort_by,
  
  // Strings
  upper: strings.upper,
  lower: strings.lower,
  trim: strings.trim,
  split: strings.split,
  join: strings.join,
  replace: strings.replace,
  starts_with: strings.starts_with,
  ends_with: strings.ends_with,
  substring: strings.substring,
  matches: strings.matches,
  
  // Numbers
  abs: numbers.abs,
  min: numbers.min,
  max: numbers.max,
  floor: numbers.floor,
  ceil: numbers.ceil,
  round: numbers.round,
  sqrt: numbers.sqrt,
  pow: numbers.pow,
  clamp: numbers.clamp,
  random: numbers.random,
  random_int: numbers.random_int,
  
  // Utility
  print: utils.print,
  log: utils.log,
  now: utils.now,
  sleep,
  typeof: utils.typeOf,
  clone: utils.clone,
  equals: utils.equals,
  hash: utils.hash,
  
  // Conversion
  to_str: utils.to_str,
  to_num: utils.to_num,
  to_json: utils.to_json,
  from_json: utils.from_json,
  
  // Concurrency
  all_settled,
  race,
  timeout,
  delay,
  
  // Sets
  set: utils.set,
  union: utils.union,
  intersect: utils.intersect,
  difference: utils.difference,
  is_subset: utils.is_subset,
  
  // Assert
  assert: utils.assert,
  
  // Errors
  error: utils.error,
  ok: utils.ok,
  err: utils.err,
};
