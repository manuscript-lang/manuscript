// Concurrency Primitives

export function spawn<T>(fn: () => Promise<T>): Promise<T> {
  return fn();
}

export function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function all_settled<T>(promises: Promise<T>[]): Promise<T[]> {
  return Promise.all(promises);
}

export async function race<T>(promises: Promise<T>[]): Promise<T> {
  return Promise.race(promises);
}

export async function timeout<T>(ms: number, promise: Promise<T>): Promise<T> {
  return Promise.race([
    promise,
    new Promise<never>((_, reject) =>
      setTimeout(() => reject(new Error("Timeout")), ms)
    ),
  ]);
}

export function delay(ms: number): Promise<void> {
  return sleep(ms);
}
