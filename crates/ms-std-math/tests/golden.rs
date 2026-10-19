//! Bit-for-bit comparison with Go's `math` package (`tests/golden/gen.go` writes the vectors).
//! `MS_MATH_GOLDEN=<file>` runs a larger set instead of the committed one.
use ms_std_math::go;

fn bits(s: &str) -> f64 {
    f64::from_bits(u64::from_str_radix(s, 16).unwrap())
}

/// Go on amd64 and arm64 computes `Exp` in assembly whose last bit depends on the CPU (FMA), so
/// the functions built on `exp` may differ from the portable algorithm by a few units in the last
/// place (and overflow marginally early); everything else must match exactly.
const EXP_FAMILY: [&str; 5] = ["exp", "sinh", "cosh", "tanh", "pow"];

fn same(name: &str, a: f64, b: f64) -> bool {
    if a.is_nan() && b.is_nan() || a.to_bits() == b.to_bits() {
        return true;
    }
    if !EXP_FAMILY.contains(&name) {
        return false;
    }
    // The assembly overflows to infinity just below the largest finite result.
    if b.is_infinite() && a.abs() > 1e307 {
        return true;
    }
    a.is_finite()
        && b.is_finite()
        && a.signum() == b.signum()
        && a.to_bits().abs_diff(b.to_bits()) <= 8
}

/// Go's amd64 `Log` assembly mishandles subnormal arguments (also reached through `pow`'s base); the portable algorithm is right.
fn go_log_quirk(name: &str, x: f64) -> bool {
    matches!(name, "log" | "log10" | "log2" | "pow") && x > 0.0 && x < f64::MIN_POSITIVE
}

#[test]
fn matches_go() {
    let text = match std::env::var("MS_MATH_GOLDEN") {
        Ok(path) => std::fs::read_to_string(path).unwrap(),
        Err(_) => include_str!("golden/golden.txt").to_string(),
    };
    let mut failures = std::collections::BTreeMap::<String, (usize, String)>::new();
    let mut total = 0usize;
    for line in text.lines() {
        let f: Vec<&str> = line.split(' ').collect();
        let (got, want) = match f[0] {
            "atan2" => (go::atan2(bits(f[1]), bits(f[2])), bits(f[3])),
            "hypot" => (go::hypot(bits(f[1]), bits(f[2])), bits(f[3])),
            "pow" => (go::pow(bits(f[1]), bits(f[2])), bits(f[3])),
            "mod" => (go::fmod(bits(f[1]), bits(f[2])), bits(f[3])),
            name => {
                let x = bits(f[1]);
                let got = match name {
                    "acos" => go::acos(x),
                    "asin" => go::asin(x),
                    "atan" => go::atan(x),
                    "cos" => go::cos(x),
                    "cosh" => go::cosh(x),
                    "exp" => go::exp(x),
                    "log" => go::log(x),
                    "log10" => go::log10(x),
                    "log2" => go::log2(x),
                    "sin" => go::sin(x),
                    "sinh" => go::sinh(x),
                    "tan" => go::tan(x),
                    "tanh" => go::tanh(x),
                    "acosh" => go::acosh(x),
                    "asinh" => go::asinh(x),
                    "atanh" => go::atanh(x),
                    "cbrt" => go::cbrt(x),
                    "expm1" => go::expm1(x),
                    "log1p" => go::log1p(x),
                    "sqrt" => go::sqrt_(x),
                    "floor" => go::floor_(x),
                    "ceil" => go::ceil_(x),
                    "trunc" => go::trunc_(x),
                    "round" => go::round(x),
                    other => panic!("unknown function {other}"),
                };
                (got, bits(f[2]))
            }
        };
        total += 1;
        if go_log_quirk(f[0], bits(f[1])) {
            continue;
        }
        if !same(f[0], got, want) {
            let e = failures
                .entry(f[0].to_string())
                .or_insert((0, String::new()));
            e.0 += 1;
            if e.1.is_empty() {
                e.1 = format!("{line} got {:016x}", got.to_bits());
            }
        }
    }
    assert!(
        failures.is_empty(),
        "{} of {total} differ: {failures:#?}",
        failures.values().map(|v| v.0).sum::<usize>()
    );
}
