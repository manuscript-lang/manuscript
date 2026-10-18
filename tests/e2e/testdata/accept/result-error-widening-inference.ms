import panic from "@std/faults.ms"

type Failure:
    code: Int

impl Error for Failure:
    fn message() String:
        return "failure " + self.code.toString()

fn failing() Result[Int, Failure]:
    return error(Failure(code: 7))

fn succeeding() Result[Int, Failure]:
    return ok(3)

fn describe[T](r: Result[T, Error]) String:
    match r:
        ok(_):
            return "ok"
        error(cause):
            return cause.message()

test "a generic Result[T, Error] parameter infers T and widens a domain error":
    if describe(r: failing()) != "failure 7":
        return panic(message: "domain error was not preserved through widening")
    if describe(r: succeeding()) != "ok":
        return panic(message: "success was not preserved through widening")
