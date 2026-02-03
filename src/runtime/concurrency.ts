// Concurrency Primitives

export class Channel<T> {
  private buffer: T[] = [];
  private capacity: number;
  private closed: boolean = false;
  private sendWaiters: Array<{ value: T; resolve: () => void }> = [];
  private recvWaiters: Array<{ resolve: (value: T | undefined) => void }> = [];

  constructor(capacity: number = 0) {
    this.capacity = capacity;
  }

  async send(value: T): Promise<void> {
    if (this.closed) throw new Error("Cannot send on closed channel");

    if (this.recvWaiters.length > 0) {
      const waiter = this.recvWaiters.shift()!;
      waiter.resolve(value);
      return;
    }

    if (this.buffer.length < this.capacity) {
      this.buffer.push(value);
      return;
    }

    return new Promise<void>((resolve) => {
      this.sendWaiters.push({ value, resolve });
    });
  }

  async receive(): Promise<T | undefined> {
    if (this.buffer.length > 0) {
      const value = this.buffer.shift()!;
      if (this.sendWaiters.length > 0) {
        const waiter = this.sendWaiters.shift()!;
        this.buffer.push(waiter.value);
        waiter.resolve();
      }
      return value;
    }

    if (this.sendWaiters.length > 0) {
      const waiter = this.sendWaiters.shift()!;
      waiter.resolve();
      return waiter.value;
    }

    if (this.closed) return undefined;

    return new Promise<T | undefined>((resolve) => {
      this.recvWaiters.push({ resolve });
    });
  }

  close(): void {
    this.closed = true;
    for (const waiter of this.recvWaiters) {
      waiter.resolve(undefined);
    }
    this.recvWaiters = [];
  }

  isClosed(): boolean {
    return this.closed;
  }

  [Symbol.asyncIterator](): AsyncIterator<T> {
    return {
      next: async () => {
        const value = await this.receive();
        if (value === undefined && this.closed) {
          return { done: true, value: undefined as any };
        }
        return { done: false, value: value as T };
      },
    };
  }
}

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
