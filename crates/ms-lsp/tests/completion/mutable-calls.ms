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
