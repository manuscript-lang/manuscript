package msruntime

// Result and Option are the native forms of a Result[T, E] or Optional[T] that
// a direct source function returns. They never appear as a Value: every
// consumer that is not a try, match or return unboxes or boxes through the
// functions below, so the Alternative representation stays the only dynamic one.
// T is a Go scalar (int64, float64, bool, string) or Value.

// Result is a checked Result; Cause is meaningful only when Failed.
type Result[T any] struct {
	Cause  Value
	Val    T
	Failed bool
}

// Option is a checked Optional; Val is meaningful only when Some.
type Option[T any] struct {
	Val  T
	Some bool
}

// Box returns the Alternative a dynamic consumer sees, typed by key.
func (r Result[T]) Box(key string) Value {
	if r.Failed {
		return Alternative{Type: key, Tag: "error", Fields: []Value{r.Cause}}
	}
	return Alternative{Type: key, Tag: "ok", Fields: []Value{r.Val}}
}

// Box returns the Alternative a dynamic consumer sees, typed by key.
func (o Option[T]) Box(key string) Value {
	if o.Some {
		return Alternative{Type: key, Tag: "some", Fields: []Value{o.Val}}
	}
	return Alternative{Type: key, Tag: "none", Fields: []Value{}}
}

// ResultOf unboxes a Result Alternative.
func ResultOf[T any](value Value) Result[T] {
	a := value.(Alternative)
	if a.Tag == "error" {
		return Result[T]{Cause: a.Fields[0], Failed: true}
	}
	val, _ := a.Fields[0].(T)
	return Result[T]{Val: val}
}

// OptionOf unboxes an Optional Alternative.
func OptionOf[T any](value Value) Option[T] {
	a := value.(Alternative)
	if a.Tag == "some" {
		val, _ := a.Fields[0].(T)
		return Option[T]{Val: val, Some: true}
	}
	return Option[T]{}
}

// ResultTry is try on a typed Result outside a statement-level early return:
// it raises the propagation Try raises, otherwise yields the payload.
func ResultTry[T any](r Result[T], scopes ...TypeScope) T {
	if r.Failed {
		cause := r.Cause
		if len(scopes) > 0 {
			cause = ViewOf("@std/Error", cause, scopes[0])
		}
		controlPanics.Add(1)
		panic(propagation{cause})
	}
	return r.Val
}

// Tag is the match tag of the result.
func (r Result[T]) Tag() string {
	if r.Failed {
		return "error"
	}
	return "ok"
}

// Tag is the match tag of the optional.
func (o Option[T]) Tag() string {
	if o.Some {
		return "some"
	}
	return "none"
}
