// std/concurrency - Concurrency primitives

extern fn resolve[T](p: Promise[T]): T
extern fn race[T](promises: list[Promise[T]]): T
extern fn timeout[T](ms: number, p: Promise[T]): Promise[T]
extern fn delay(ms: number): Promise[void]
extern fn sleep(ms: number): void
