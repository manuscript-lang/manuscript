# conform: tags=control-flow,diagnostics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/redundant_labels_test.go:11 TestDropRedundantLabels
type Point:
    x: Int
    y: Int

def bump(map: Int, key: Int, step: Int = 1) -> Int: map + key + step

type Counter:
    total: Int

interface Adder:
    def add(amount: Int, extra: Int) -> Int

impl Adder for Counter:
    def add(amount: Int, extra: Int) -> Int: self.total + amount + extra

def use(map: Int, key: Int, y: Int, x: Int, counter: Counter) -> Int: ...
