export fn erase[T](r: T!) T!: r

export fn forward[T, E: Error](r: T!E) T!: erase(r)
