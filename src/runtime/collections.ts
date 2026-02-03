// Collection Functions

export function len(x: any): number {
  if (typeof x === "string" || Array.isArray(x)) return x.length;
  if (x instanceof Map || x instanceof Set) return x.size;
  if (typeof x === "object" && x !== null) return Object.keys(x).length;
  return 0;
}

export function keys<K, V>(map: Map<K, V> | Record<string, V>): K[] {
  if (map instanceof Map) return Array.from(map.keys());
  return Object.keys(map) as K[];
}

export function values<K, V>(map: Map<K, V> | Record<string, V>): V[] {
  if (map instanceof Map) return Array.from(map.values());
  return Object.values(map);
}

export function entries<K, V>(map: Map<K, V> | Record<string, V>): [K, V][] {
  if (map instanceof Map) return Array.from(map.entries());
  return Object.entries(map) as [K, V][];
}

export function contains<T>(list: T[], item: T): boolean {
  return list.includes(item);
}

export function unique<T>(list: T[]): T[] {
  return [...new Set(list)];
}

export function flatten<T>(list: T[][]): T[] {
  return list.flat();
}

export function sort<T>(list: T[]): T[] {
  return [...list].sort();
}

export function reverse<T>(list: T[]): T[] {
  return [...list].reverse();
}

export function first<T>(list: T[]): T | undefined {
  return list[0];
}

export function last<T>(list: T[]): T | undefined {
  return list[list.length - 1];
}

export function take<T>(list: T[], n: number): T[] {
  return list.slice(0, n);
}

export function drop<T>(list: T[], n: number): T[] {
  return list.slice(n);
}

export function zip<T, U>(a: T[], b: U[]): [T, U][] {
  const result: [T, U][] = [];
  const len = Math.min(a.length, b.length);
  for (let i = 0; i < len; i++) {
    result.push([a[i]!, b[i]!]);
  }
  return result;
}

export async function map<T, U>(list: T[], fn: (item: T) => U | Promise<U>): Promise<U[]> {
  return Promise.all(list.map(fn));
}

export async function each<T, U>(list: T[], fn: (item: T) => U | Promise<U>): Promise<U[]> {
  return Promise.all(list.map(fn));
}

export async function filter<T>(list: T[], pred: (item: T) => boolean | Promise<boolean>): Promise<T[]> {
  const results = await Promise.all(list.map(async (item) => ({ item, keep: await pred(item) })));
  return results.filter(r => r.keep).map(r => r.item);
}

export function slice<T>(list: T[], start: number, end?: number): T[] {
  return list.slice(start, end);
}

export function concat<T>(...lists: T[][]): T[] {
  return ([] as T[]).concat(...lists);
}

export async function reduce<T, U>(list: T[], init: U, fn: (acc: U, item: T) => U | Promise<U>): Promise<U> {
  let acc = init;
  for (const item of list) {
    acc = await fn(acc, item);
  }
  return acc;
}

export async function find<T>(list: T[], pred: (item: T) => boolean | Promise<boolean>): Promise<T | undefined> {
  for (const item of list) {
    if (await pred(item)) return item;
  }
  return undefined;
}

export async function any<T>(list: T[], pred: (item: T) => boolean | Promise<boolean>): Promise<boolean> {
  for (const item of list) {
    if (await pred(item)) return true;
  }
  return false;
}

export async function all<T>(list: T[], pred: (item: T) => boolean | Promise<boolean>): Promise<boolean> {
  for (const item of list) {
    if (!(await pred(item))) return false;
  }
  return true;
}

export async function group_by<T, K extends string | number>(
  list: T[],
  fn: (item: T) => K | Promise<K>
): Promise<Map<K, T[]>> {
  const result = new Map<K, T[]>();
  for (const item of list) {
    const key = await fn(item);
    if (!result.has(key)) result.set(key, []);
    result.get(key)!.push(item);
  }
  return result;
}

export async function sort_by<T, K>(list: T[], fn: (item: T) => K | Promise<K>): Promise<T[]> {
  const pairs = await Promise.all(list.map(async (item) => ({ item, key: await fn(item) })));
  pairs.sort((a, b) => {
    if (a.key < b.key) return -1;
    if (a.key > b.key) return 1;
    return 0;
  });
  return pairs.map(p => p.item);
}
