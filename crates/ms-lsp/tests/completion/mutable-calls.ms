export fn update(var values: List[Int], amount: Int = 1) Int:
    values.append(amount)
    return values.length()

export fn observe(values: List[Int], amount: Int = 1) Int:
    return values.length() + amount

type Updater:
    amount: Int

impl Updater:
    fn adjust(values: List[Int], amount: Int = 1) Int:
        return values.length() + self.amount + amount

fn direct() Int:
    var values = [1]
    return update(values: var values)

fn method() Int:
    var values = [1]
    let updater = Updater(2)
    return updater.adjust(values: values)

fn ordinary() Int:
    let values = [1]
    return observe(values: values)

export fn update_generic[T](var values: List[T], value: T) Int:
    values.append(value)
    return values.length()

fn generic() Int:
    var values = [1]
    return update_generic[Int](values: var values, value: 2)
