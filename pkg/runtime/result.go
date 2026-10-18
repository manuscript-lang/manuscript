package msruntime

// Result_IsOk reports success.
func Result_IsOk[T, E any](_ *Execution, r Result[T, E]) bool { return !r.Failed }

// Result_IsError reports failure.
func Result_IsError[T, E any](_ *Execution, r Result[T, E]) bool { return r.Failed }

// Result_Get returns the success payload, else the default; an error
// without a default is a fault.
func Result_Get[T, E any](_ *Execution, r Result[T, E], def Option[T]) T {
	if !r.Failed {
		return r.Val
	}
	if def.Some {
		return def.Val
	}
	Raise("called Result.get() on error; check is_ok first, or pass a default: get(default: ...)")
	panic("unreachable")
}

// Result_Err returns the error payload; success is a fault.
func Result_Err[T, E any](_ *Execution, r Result[T, E]) E {
	if !r.Failed {
		Raise("called Result.err() on ok; check is_error first")
	}
	return r.Err
}

// Result_OrElse returns the success payload or create(cause).
func Result_OrElse[T, E any](ctx *Execution, r Result[T, E], create func(*Execution, E) T) T {
	if r.Failed {
		return create(ctx, r.Err)
	}
	return r.Val
}

// Result_Map transforms the success payload, retaining an error as is.
func Result_Map[T, E, U any](ctx *Execution, r Result[T, E], transform func(*Execution, T) U) Result[U, E] {
	if r.Failed {
		return Fail[U, E](r.Err)
	}
	return Ok[U, E](transform(ctx, r.Val))
}

// Result_AndThen chains a Result-returning transform.
func Result_AndThen[T, E, U any](ctx *Execution, r Result[T, E], transform func(*Execution, T) Result[U, E]) Result[U, E] {
	if r.Failed {
		return Fail[U, E](r.Err)
	}
	return transform(ctx, r.Val)
}

// Result_ToOptional keeps a success payload and drops an error.
func Result_ToOptional[T, E any](_ *Execution, r Result[T, E]) Option[T] {
	if r.Failed {
		return Option[T]{}
	}
	return Some(r.Val)
}

// ResultMapError converts the error payload of a failed Result, as at an
// Error boundary. A success keeps its payload.
func ResultMapError[T, E, F any](r Result[T, E], f func(E) F) Result[T, F] {
	if r.Failed {
		return Fail[T, F](f(r.Err))
	}
	return Ok[T, F](r.Val)
}
