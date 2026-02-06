// std/concurrency - Concurrency primitives

extern type Channel[T]
  buffer?: number
  fn send(value: T): void
  fn receive(): T?
  fn close(): void
  fn try_send(value: T): bool
  fn try_receive(): T?
  fn isClosed(): bool

extern fn race[T](promises: list[Promise[T]]): Promise[T]
extern fn timeout[T](ms: number, p: Promise[T]): Promise[T]
extern fn delay(ms: number): Promise[void]
extern fn sleep(ms: number): void
