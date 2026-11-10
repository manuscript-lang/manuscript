import (
    stdout from "@std/io/io.ms",
    monotonic from "@std/time.ms",
    parse from "@std/data/csv.ms",
)

// Parses 5000 rows 200 times and prints the best run in microseconds.
// The "quoted" shape has quoted and escaped cells; "plain" has none.
fn rows_of(shape: String) String:
    var text = ""

    for i in 0..5000:
        if shape == "quoted": text = text.concat(
            "{i},name {i},\"a,b\",\"quote\"\"d\"\n"
        )
        else: text = text.concat("{i},name {i},alpha,beta,gamma\n")

    return text

fn main() Unit:
    for shape in ["quoted", "plain"]:
        text := rows_of(shape)
        var best = 9223372036854775807
        var count = 0

        for _round in 0..200:
            started := monotonic()
            result := parse(text)
            elapsed := monotonic().difference(started).to_nanoseconds()
            count = result.get().length()
            if elapsed < best: best = elapsed

        _written := stdout().write(
            "manuscript {shape} rows={count} best_us={best / 1000}\n"
        )
