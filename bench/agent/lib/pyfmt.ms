# Number formatting that matches CPython's format specs, so regenerated Markdown tables stay identical.
import round from "@std/math.ms"

# Drops trailing zeros after a decimal point, and the point itself when nothing follows it.
fn strip_zeros(text: String) String:
    if not text.contains("."): return text.clone()

    var out = text.clone()
    while out.ends_with("0"): out = out.slice(0, out.length() - 1).get("")
    if out.ends_with("."): out = out.slice(0, out.length() - 1).get("")
    return out

# `format(x, ".{places}f")`. CPython rounds the exact binary value, and an exact tie goes to the even digit,
# where `to_fixed` rounds it up.
export fn fixed(x: Float, places: Int) String:
    let wide = x.abs().to_fixed(places + 30)
    let at = wide.index_of(".").get(wide.length())
    let cut = at + 1 + places
    let tail = wide.slice(cut, wide.length()).get("")
    let tie = (
        tail.starts_with("5")
        and tail.slice(1, tail.length()).get("").replace("0", "") == ""
    )
    if not tie: return x.to_fixed(places)

    var kept = wide.slice(0, cut).get("")
    if places == 0: kept = wide.slice(0, at).get("")

    let last = kept.get(kept.length() - 1).parse_int().get(0)
    if last % 2 == 1: return x.to_fixed(places)

    return if x < 0.0: "-" + kept else: kept

# `format(x, ".{digits}g")`.
export fn fmt_g(x: Float, digits: Int) String:
    if x == 0.0: return "0"

    let sci = x.abs().to_exponential(digits - 1)
    let exp = sci.split("e")[1].replace("+", "").parse_int().get(0)

    if exp < -4 or exp >= digits:
        let mantissa = strip_zeros(x.to_exponential(digits - 1).split("e")[0])

        let sign = if exp < 0: "-" else: "+"

        let mag = "{if exp < 0: 0 - exp else: exp}".pad_start(2, "0")
        return "{mantissa}e{sign}{mag}"

    return strip_zeros(fixed(x, digits - 1 - exp))

# `format(x, ".0%")`.
export fn pct0(x: Float) String: fixed(x * 100.0, 0) + "%"

# The mean of values that carry at most `scale`-ths of precision (wall times to 0.1 s use 10.0), computed from
# exact integer sums so the result is the correctly rounded quotient, as CPython's `statistics.mean` gives.
export fn mean_scaled(values: List[Float], scale: Float) Float:
    let total = values.map(fn v: round(v * scale).truncate_to_int().get(0)).sum()
    return total.to_float() / (values.length().to_float() * scale)
