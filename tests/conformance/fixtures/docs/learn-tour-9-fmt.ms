# conform: tags=alternatives,control-flow,formatter,parser,records,tier-core,try-result
# conform: phase=parse
# conform: origin=documentation/learn/tour.md:172
type QuantityError:
    case MustBePositive

fn quantity(value: Int) Result[Int, QuantityError]:
    if value <= 0:
        return error(QuantityError.MustBePositive)

    return ok(value)

fn order_total(count: Int) Result[Int, QuantityError]:
    let valid_count = try quantity(count)
    return ok(valid_count * 12)
