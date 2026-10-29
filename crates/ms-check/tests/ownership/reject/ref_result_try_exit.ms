type Failed:
    detail: String

impl Error for Failed:
    fn message() String:
        return self.detail.clone()

type Recorded:
    result: Result[String, Failed]

fn checked(n: Int) Result[Int, Failed]:
    if n < 0:
        return error(Failed(detail: "negative"))

    return ok(n)

fn stored(r: Recorded, n: Int) ref Result[String, Failed]:
    let i = try checked(n)  # error: so every path must return part of a parameter
    return r.result
