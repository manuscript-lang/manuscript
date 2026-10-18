import panic from "@std/faults.ms"

type Failure:
    code: Int

impl Error for Failure:
    fn message() String:
        return "failure " + self.code.toString()

fn failing() Result[Int, Failure]:
    return error(Failure(7))

fn succeeding() Result[Int, Failure]:
    return ok(3)

fn describe[T](r: Result[T, Error]) String:
    if r.is_error():
        return r.unwrap_error().message()

    return "ok"

test "a generic Result[T, Error] parameter infers T and widens a domain error":
    if describe(failing()) != "failure 7":
        return panic("domain error was not preserved through widening")
    if describe(succeeding()) != "ok":
        return panic("success was not preserved through widening")
