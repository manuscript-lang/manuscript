type Cause:
    code: Int

impl Error for Cause:
    fn message() String: "cause {self.code}"

fn first_error(cause: Cause) Error:
    return cause

fn store_local(cause: Cause) List[Error]:
    let e: Error = cause
    return [e]  # error: an interface value cannot be cloned (convert a clone of the concrete value instead), so use `e` in place

fn store_call(var xs: List[Error], cause: Cause) Unit:
    xs.append(first_error(cause))  # error: an interface value cannot be cloned (convert a clone of the concrete value instead), so use it in place

fn capture(cause: Cause) fn() String:
    let e = first_error(cause)
    return fn: e.message()  # error: an interface value cannot be cloned (convert a clone of the concrete value instead), so capture an owned value instead

fn change_held(var cause: Cause) Error:
    let e = first_error(cause)
    cause.code = 2  # error: finish using `e` before this, or give `e` its own value by converting a clone of the concrete value
    return e
