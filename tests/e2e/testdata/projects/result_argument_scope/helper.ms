export def erase[T](r: Result[T, Error]) -> Result[T, Error]: r

export def forward[T, E: Error](r: Result[T, E]) -> Result[T, Error]: erase(r)
