import {Decimal, RoundingMode} from "@std/decimal.ms"
import NumberError from "@std/numbers.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

test "decimal cents stay exact and fixed places retain zeros":
    let total = 19.99d * 3d
    let tax = value((total * 0.0825d).round(places: 2))
    if tax != 4.95d: return panic("tax rounding")
    if value(tax.to_fixed(digits: 2)) != "4.95": return panic("tax formatting")
    if value((total + tax).to_fixed(digits: 2)) != "64.92": return panic(
        "total formatting"
    )
    if value(25.50d.to_fixed(digits: 2)) != "25.50": return panic("trailing zero")
    if value(9007199254740993.125d.to_fixed(digits: 2)) != "9007199254740993.12": return panic(
        "binary conversion"
    )
    if "{25.50d}" != "25.5": return panic("normalized interpolation changed")
    if 1d / 3d != 0.3333333333333333333333333333333333d: return panic(
        "arithmetic changed"
    )

test "decimal rounding modes include signed ties and coarse scales":
    if value(2.5d.round(places: 0, mode: none)) != 2d: return panic("default even tie")
    if value(3.5d.round(places: 0)) != 4d: return panic("default odd tie")
    if value((-2.5d).round(places: 0)) != -2d: return panic("negative even tie")
    if value((-2.5d).round(places: 0, mode: RoundingMode.HalfAwayFromZero)) != -3d: return panic(
        "away tie"
    )
    if value((-2.9d).round(places: 0, mode: RoundingMode.TowardZero)) != -2d: return panic(
        "toward zero"
    )
    if value((-2.1d).round(places: 0, mode: RoundingMode.Floor)) != -3d: return panic(
        "floor"
    )
    if value((-2.1d).round(places: 0, mode: RoundingMode.Ceil)) != -2d: return panic(
        "ceil"
    )
    if value(1250d.round(places: -2)) != 1200d: return panic("coarse even tie")
    if value((-0.005d).to_fixed(digits: 2)) != "0.00": return panic("rounded zero")
    if value((-0.005d).to_fixed(digits: 2, mode: RoundingMode.Floor)) != "-0.01": return panic(
        "fixed mode"
    )

    let fixed = 25.5d.to_fixed
    if value(fixed(digits: 2)) != "25.50": return panic("bound default")

    let rounded: fn(places: Int, mode: Optional[RoundingMode]) Result[
        Decimal,
        NumberError
    ] = 2.5d.round
    if value(rounded(places: 0, mode: RoundingMode.HalfEven)) != 2d: return panic(
        "typed bound method"
    )

test "decimal scale extremes and invalid requests return typed errors":
    if value(1e-6176d.round(places: 6176)) != 1e-6176d: return panic("minimum scale")
    if value(5e-6176d.round(places: 6175)) != 0d: return panic("subnormal tie")
    if value(1e6144d.round(places: -6144)) != 1e6144d: return panic("maximum scale")
    if value(0d.to_fixed(digits: 6176)).scalar_length() != 6178: return panic(
        "maximum digits"
    )

    let invalid_round: Result[Decimal, NumberError] = error(NumberError.InvalidInput)
    if 0d.round(places: -6145) != invalid_round: return panic("invalid places")
    if 0d.round(places: 6177) != invalid_round: return panic("invalid places")

    let invalid_fixed: Result[String, NumberError] = error(NumberError.InvalidInput)
    if 0d.to_fixed(digits: -1) != invalid_fixed: return panic("invalid digits")
    if 0d.to_fixed(digits: 6177) != invalid_fixed: return panic("invalid digits")

    let overflow: Result[Decimal, NumberError] = error(NumberError.OutOfRange)
    if 9.999999999999999999999999999999999e6144d.round(places: -6144) != overflow: return panic(
        "round overflow"
    )
