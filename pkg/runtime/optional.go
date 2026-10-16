package msruntime

import "strings"

const unwrapNoneMessage = "called Optional.unwrap() on none; check is_some first, or use unwrap_or(fallback: ...) to supply a default"

// Optional_IsSome reports whether a payload is present.
func Optional_IsSome[T any](_ *Execution, o Option[T]) bool { return o.Some }

// Optional_IsNone reports whether the Optional is empty.
func Optional_IsNone[T any](_ *Execution, o Option[T]) bool { return !o.Some }

// Optional_Unwrap returns the payload; none is a fault.
func Optional_Unwrap[T any](ctx *Execution, o Option[T]) T {
	CheckCancelled(ctx)
	if !o.Some {
		Raise(unwrapNoneMessage)
	}
	return o.Val
}

// Optional_UnwrapOr returns the payload or fallback.
func Optional_UnwrapOr[T any](_ *Execution, o Option[T], fallback T) T {
	if o.Some {
		return o.Val
	}
	return fallback
}

// Optional_UnwrapOrElse returns the payload or create(), called only for none.
func Optional_UnwrapOrElse[T any](ctx *Execution, o Option[T], create func(*Execution) T) T {
	if o.Some {
		return o.Val
	}
	return create(ctx)
}

// Optional_Map transforms a present payload.
func Optional_Map[T, U any](ctx *Execution, o Option[T], transform func(*Execution, T) U) Option[U] {
	if !o.Some {
		return Option[U]{}
	}
	return Some(transform(ctx, o.Val))
}

// Optional_AndThen chains an Optional-returning transform.
func Optional_AndThen[T, U any](ctx *Execution, o Option[T], transform func(*Execution, T) Option[U]) Option[U] {
	if !o.Some {
		return Option[U]{}
	}
	return transform(ctx, o.Val)
}

// Optional_OrElse keeps a present value, else calls create().
func Optional_OrElse[T any](ctx *Execution, o Option[T], create func(*Execution) Option[T]) Option[T] {
	if o.Some {
		return o
	}
	return create(ctx)
}

// Optional_OkOr converts to a Result with an eager cause. Without a cause the
// error type must be MissingValue, which names the calling source position.
func Optional_OkOr[T, E any](_ *Execution, o Option[T], cause Option[E]) Result[T, E] {
	if o.Some {
		return Ok[T, E](o.Val)
	}
	if cause.Some {
		return Fail[T, E](cause.Val)
	}
	var e E
	slot, ok := any(&e).(*MissingValue)
	if !ok {
		Raise("called Optional.ok_or() without a cause for an error type other than MissingValue")
	}
	location := "unknown location"
	if frames, _ := captureFrames(); len(frames) > 0 {
		location, _, _ = strings.Cut(frames[0], " in ")
	}
	*slot = MissingValue_Missing{Location: location}
	return Fail[T, E](e)
}

// Optional_OkOrElse converts to a Result, creating the error only for none.
func Optional_OkOrElse[T, E any](ctx *Execution, o Option[T], create func(*Execution) E) Result[T, E] {
	if o.Some {
		return Ok[T, E](o.Val)
	}
	return Fail[T, E](create(ctx))
}
