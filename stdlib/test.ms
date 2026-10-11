# Canonical standard-library declarations. Implementations are native.


export fn assert_equal[T: Equal](actual: T, expected: T) -> Unit

export fn assert_near(actual: Float, expected: Float, absolute: Float, relative: Float) -> Unit
