// conform: tags=diagnostics
// conform: phase=check
type Point:
    x: Int
    y: Int

fn bump(map: Int, key: Int, step: Int = 1) Int: map + key + step

type Counter:
    total: Int

interface Adder:
    fn add(amount: Int, extra: Int) Int

impl Adder for Counter:
    fn add(amount: Int, extra: Int) Int: self.total + amount + extra

fn use(map: Int, key: Int, y: Int, x: Int, counter: Counter) Int: ...
