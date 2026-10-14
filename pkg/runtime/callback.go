package msruntime

// callback calls one library argument repeatedly; callers pass the operation to
// each call so the callback's field-insensitive escape state never captures it. Each library invocation owns
// its callback and argument buffer, so recursion and reentry never share one.
// Only compiled bodies with exactly the expected labels borrow the buffer
// (they copy incoming Values up front); anything else goes through Invoke.
type callback struct {
	body   func(*Execution, []Value) Value
	args   []Value
	first  string
	second string
}

func newCallback(operation Value, first string) callback {
	c := callback{first: first}
	if function, ok := operation.(Function); ok && function.BorrowedArguments && len(function.Labels) == 1 && function.Labels[0] == first {
		c.body = function.Body
	}
	return c
}

func newCallback2(operation Value, first, second string) callback {
	c := callback{first: first, second: second}
	if function, ok := operation.(Function); ok && function.BorrowedArguments && len(function.Labels) == 2 && function.Labels[0] == first && function.Labels[1] == second {
		c.body = function.Body
	}
	return c
}

func (c *callback) call1(ctx *Execution, operation, value Value) Value {
	if c.body == nil {
		return Invoke(ctx, operation, []Argument{{c.first, value}})
	}
	if c.args == nil {
		c.args = make([]Value, 1)
	}
	c.args[0] = value
	// Invoke's admission checkpoint; the guarded Body owns source admission.
	CheckCancelled(ctx)
	return c.body(ctx, c.args)
}

func (c *callback) call2(ctx *Execution, operation, first, second Value) Value {
	if c.body == nil {
		return Invoke(ctx, operation, []Argument{{c.first, first}, {c.second, second}})
	}
	if c.args == nil {
		c.args = make([]Value, 2)
	}
	c.args[0], c.args[1] = first, second
	CheckCancelled(ctx)
	return c.body(ctx, c.args)
}
