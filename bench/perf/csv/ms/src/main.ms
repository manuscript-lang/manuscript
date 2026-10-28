from "@std/io.ms" import stdout
from "@std/time.ms" import clock
from "@std/csv.ms" import parse

# Parses 5000 rows 200 times and prints the best run in microseconds.
# The "quoted" shape has quoted and escaped cells; "plain" has none.
def rows_of(shape: String) -> String:
    var text = ""

    for i in 0..5000:
        if shape == "quoted": text = text.concat(
            f"{i},name {i},\"a,b\",\"quote\"\"d\"\n"
        )
        else: text = text.concat(f"{i},name {i},alpha,beta,gamma\n")

    return text

export def main() -> Int:
    for shape in ["quoted", "plain"]:
        let text = rows_of(shape)
        var best = 9223372036854775807
        var count = 0

        for _round in 0..200:
            let started = clock().now()
            let result = parse(text)
            let elapsed = clock().now().difference(started).to_nanoseconds()
            count = result.get().length()
            if elapsed < best: best = elapsed

        let _written = stdout().write(
            f"manuscript {shape} rows={count} best_us={best / 1000}\n"
        )

    return 0
