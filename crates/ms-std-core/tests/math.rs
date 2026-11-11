// Links the msrt_* runtime symbols.
use ms_rt as _;
use ms_std_core::math::*;

#[test]
fn round_ties_toward_positive_infinity() {
    assert_eq!(msstd_math_round(2.5), 3.0);
    assert_eq!(msstd_math_round(-2.5), -2.0);
    assert!(msstd_math_round(-0.2).is_sign_negative());
}

#[test]
fn special_values() {
    assert_eq!(msstd_math_pow(1.0, f64::NAN), 1.0);
    assert!(msstd_math_sqrt(-1.0).is_nan());
    assert_eq!(msstd_math_log(0.0), f64::NEG_INFINITY);
    assert_eq!(msstd_math_remainder(5.5, 2.0), 1.5);
    assert_eq!(msstd_math_hypot(3.0, 4.0), 5.0);
    assert_eq!(msstd_math_is_integer(3.0), 1);
    assert_eq!(msstd_math_is_integer(f64::INFINITY), 0);
}
