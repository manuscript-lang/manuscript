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

export function map<T, U>(list: T[], fn: (item: T) => U): U[] {
  return list.map(fn);
}

export function each<T, U>(list: T[], fn: (item: T) => U): U[] {
  return list.map(fn);
}

export function filter<T>(list: T[], pred: (item: T) => boolean): T[] {
  return list.filter(pred);
}

export function slice<T>(list: T[], start: number, end?: number): T[] {
  return list.slice(start, end);
}

export function concat<T>(...lists: T[][]): T[] {
  return ([] as T[]).concat(...lists);
}

export function reduce<T, U>(list: T[], init: U, fn: (acc: U, item: T) => U): U {
  return list.reduce(fn, init);
}

export function find<T>(list: T[], pred: (item: T) => boolean): T | undefined {
  return list.find(pred);
}

export function any<T>(list: T[], pred: (item: T) => boolean): boolean {
  return list.some(pred);
}

export function all<T>(list: T[], pred: (item: T) => boolean): boolean {
  return list.every(pred);
}

export function group_by<T, K extends string | number>(
  list: T[],
  fn: (item: T) => K
): Map<K, T[]> {
  const result = new Map<K, T[]>();
  for (const item of list) {
    const key = fn(item);
    if (!result.has(key)) result.set(key, []);
    result.get(key)!.push(item);
  }
  return result;
}

export function sort_by<T, K>(list: T[], fn: (item: T) => K): T[] {
  return [...list].sort((a, b) => {
    const ka = fn(a);
    const kb = fn(b);
    if (ka < kb) return -1;
    if (ka > kb) return 1;
    return 0;
  });
}
