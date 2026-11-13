// Closures, indirect calls and runtime calls, emitted straight from MIR. The padding keeps the
// inliner from folding these functions into `main`.
fn make_scaler(scale: Float, shift: Float, flip: Bool) fn(Float) Float:
    var pad = scale
    pad = pad * 1.0001 + 0.5
    pad = pad * 1.0001 + 1.5
    pad = pad * 1.0001 + 2.5
    pad = pad * 1.0001 + 3.5
    pad = pad * 1.0001 + 4.5
    pad = pad * 1.0001 + 5.5
    pad = pad * 1.0001 + 6.5
    pad = pad * 1.0001 + 7.5
    pad = pad * 1.0001 + 8.5
    pad = pad * 1.0001 + 9.5
    pad = pad * 1.0001 + 10.5
    pad = pad * 1.0001 + 11.5
    pad = pad * 1.0001 + 12.5
    pad = pad * 1.0001 + 13.5
    pad = pad * 1.0001 + 14.5
    pad = pad * 1.0001 + 15.5
    pad = pad * 1.0001 + 16.5
    pad = pad * 1.0001 + 17.5
    pad = pad * 1.0001 + 18.5
    pad = pad * 1.0001 + 19.5
    pad = pad * 1.0001 + 20.5
    pad = pad * 1.0001 + 21.5
    pad = pad * 1.0001 + 22.5
    pad = pad * 1.0001 + 23.5
    pad = pad * 1.0001 + 24.5
    pad = pad * 1.0001 + 25.5
    pad = pad * 1.0001 + 26.5
    pad = pad * 1.0001 + 27.5
    pad = pad * 1.0001 + 28.5
    pad = pad * 1.0001 + 29.5
    pad = pad * 1.0001 + 30.5
    pad = pad * 1.0001 + 31.5
    pad = pad * 1.0001 + 32.5
    pad = pad * 1.0001 + 33.5
    pad = pad * 1.0001 + 34.5
    pad = pad * 1.0001 + 35.5
    pad = pad * 1.0001 + 36.5
    pad = pad * 1.0001 + 37.5
    pad = pad * 1.0001 + 38.5
    pad = pad * 1.0001 + 39.5
    pad = pad * 1.0001 + 40.5
    pad = pad * 1.0001 + 41.5
    pad = pad * 1.0001 + 42.5
    pad = pad * 1.0001 + 43.5
    pad = pad * 1.0001 + 44.5
    pad = pad * 1.0001 + 45.5
    pad = pad * 1.0001 + 46.5
    pad = pad * 1.0001 + 47.5
    pad = pad * 1.0001 + 48.5
    pad = pad * 1.0001 + 49.5
    pad = pad * 1.0001 + 50.5
    pad = pad * 1.0001 + 51.5
    pad = pad * 1.0001 + 52.5
    pad = pad * 1.0001 + 53.5
    pad = pad * 1.0001 + 54.5
    pad = pad * 1.0001 + 55.5
    pad = pad * 1.0001 + 56.5
    pad = pad * 1.0001 + 57.5
    pad = pad * 1.0001 + 58.5
    pad = pad * 1.0001 + 59.5
    return fn(x: Float) Float:
        if flip:
            return x * scale + shift + pad * 0.0
        return x - shift

fn make_counter(xs: List[Float], label: String, bias: Float, big: Bool) fn(Float) Float:
    var pad = bias
    pad = pad * 1.0001 + 0.5
    pad = pad * 1.0001 + 1.5
    pad = pad * 1.0001 + 2.5
    pad = pad * 1.0001 + 3.5
    pad = pad * 1.0001 + 4.5
    pad = pad * 1.0001 + 5.5
    pad = pad * 1.0001 + 6.5
    pad = pad * 1.0001 + 7.5
    pad = pad * 1.0001 + 8.5
    pad = pad * 1.0001 + 9.5
    pad = pad * 1.0001 + 10.5
    pad = pad * 1.0001 + 11.5
    pad = pad * 1.0001 + 12.5
    pad = pad * 1.0001 + 13.5
    pad = pad * 1.0001 + 14.5
    pad = pad * 1.0001 + 15.5
    pad = pad * 1.0001 + 16.5
    pad = pad * 1.0001 + 17.5
    pad = pad * 1.0001 + 18.5
    pad = pad * 1.0001 + 19.5
    pad = pad * 1.0001 + 20.5
    pad = pad * 1.0001 + 21.5
    pad = pad * 1.0001 + 22.5
    pad = pad * 1.0001 + 23.5
    pad = pad * 1.0001 + 24.5
    pad = pad * 1.0001 + 25.5
    pad = pad * 1.0001 + 26.5
    pad = pad * 1.0001 + 27.5
    pad = pad * 1.0001 + 28.5
    pad = pad * 1.0001 + 29.5
    pad = pad * 1.0001 + 30.5
    pad = pad * 1.0001 + 31.5
    pad = pad * 1.0001 + 32.5
    pad = pad * 1.0001 + 33.5
    pad = pad * 1.0001 + 34.5
    pad = pad * 1.0001 + 35.5
    pad = pad * 1.0001 + 36.5
    pad = pad * 1.0001 + 37.5
    pad = pad * 1.0001 + 38.5
    pad = pad * 1.0001 + 39.5
    pad = pad * 1.0001 + 40.5
    pad = pad * 1.0001 + 41.5
    pad = pad * 1.0001 + 42.5
    pad = pad * 1.0001 + 43.5
    pad = pad * 1.0001 + 44.5
    pad = pad * 1.0001 + 45.5
    pad = pad * 1.0001 + 46.5
    pad = pad * 1.0001 + 47.5
    pad = pad * 1.0001 + 48.5
    pad = pad * 1.0001 + 49.5
    pad = pad * 1.0001 + 50.5
    pad = pad * 1.0001 + 51.5
    pad = pad * 1.0001 + 52.5
    pad = pad * 1.0001 + 53.5
    pad = pad * 1.0001 + 54.5
    pad = pad * 1.0001 + 55.5
    pad = pad * 1.0001 + 56.5
    pad = pad * 1.0001 + 57.5
    pad = pad * 1.0001 + 58.5
    pad = pad * 1.0001 + 59.5
    return fn(x: Float) Float:
        if xs.length() > 2 and big:
            return x * bias + pad * 0.0
        return x + bias

fn show(n: Int, bias: Float) String:
    var pad = bias
    pad = pad * 1.0001 + 0.5
    pad = pad * 1.0001 + 1.5
    pad = pad * 1.0001 + 2.5
    pad = pad * 1.0001 + 3.5
    pad = pad * 1.0001 + 4.5
    pad = pad * 1.0001 + 5.5
    pad = pad * 1.0001 + 6.5
    pad = pad * 1.0001 + 7.5
    pad = pad * 1.0001 + 8.5
    pad = pad * 1.0001 + 9.5
    pad = pad * 1.0001 + 10.5
    pad = pad * 1.0001 + 11.5
    pad = pad * 1.0001 + 12.5
    pad = pad * 1.0001 + 13.5
    pad = pad * 1.0001 + 14.5
    pad = pad * 1.0001 + 15.5
    pad = pad * 1.0001 + 16.5
    pad = pad * 1.0001 + 17.5
    pad = pad * 1.0001 + 18.5
    pad = pad * 1.0001 + 19.5
    pad = pad * 1.0001 + 20.5
    pad = pad * 1.0001 + 21.5
    pad = pad * 1.0001 + 22.5
    pad = pad * 1.0001 + 23.5
    pad = pad * 1.0001 + 24.5
    pad = pad * 1.0001 + 25.5
    pad = pad * 1.0001 + 26.5
    pad = pad * 1.0001 + 27.5
    pad = pad * 1.0001 + 28.5
    pad = pad * 1.0001 + 29.5
    pad = pad * 1.0001 + 30.5
    pad = pad * 1.0001 + 31.5
    pad = pad * 1.0001 + 32.5
    pad = pad * 1.0001 + 33.5
    pad = pad * 1.0001 + 34.5
    pad = pad * 1.0001 + 35.5
    pad = pad * 1.0001 + 36.5
    pad = pad * 1.0001 + 37.5
    pad = pad * 1.0001 + 38.5
    pad = pad * 1.0001 + 39.5
    pad = pad * 1.0001 + 40.5
    pad = pad * 1.0001 + 41.5
    pad = pad * 1.0001 + 42.5
    pad = pad * 1.0001 + 43.5
    pad = pad * 1.0001 + 44.5
    pad = pad * 1.0001 + 45.5
    pad = pad * 1.0001 + 46.5
    pad = pad * 1.0001 + 47.5
    pad = pad * 1.0001 + 48.5
    pad = pad * 1.0001 + 49.5
    pad = pad * 1.0001 + 50.5
    pad = pad * 1.0001 + 51.5
    pad = pad * 1.0001 + 52.5
    pad = pad * 1.0001 + 53.5
    pad = pad * 1.0001 + 54.5
    pad = pad * 1.0001 + 55.5
    pad = pad * 1.0001 + 56.5
    pad = pad * 1.0001 + 57.5
    pad = pad * 1.0001 + 58.5
    pad = pad * 1.0001 + 59.5
    if pad > 1.0e300:
        return pad.to_string()
    return n.to_string()

fn fold(f: fn(Float) Float, start: Float, steps: Float) Float:
    var acc = start
    var i = 0.0
    while i < steps:
        acc = f(acc)
        i = i + 1.0
    return acc

fn main() Int:
    scale := make_scaler(1.5, 2.0, true)
    shift := make_scaler(1.5, 2.0, false)
    counter := make_counter([1.0, 2.0, 3.0], "three", 0.5, true)
    small := make_counter([1.0], "one", 0.5, true)
    print(fold(scale, 1.0, 5.0))
    print(fold(shift, 10.0, 5.0))
    print(fold(counter, 1.0, 4.0))
    print(fold(small, 1.0, 4.0))
    print(show(7, 1.0))
    return 0
