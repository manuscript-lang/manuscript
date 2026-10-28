export fn erase[T](r: Result[T, Error]) Result[T, Error]: r

export fn forward[T, E: Error](r: Result[T, E]) Result[T, Error]: erase(r)
