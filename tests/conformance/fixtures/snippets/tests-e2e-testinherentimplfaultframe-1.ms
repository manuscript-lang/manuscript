# conform: tags=interfaces,records,testing,tier-core
# conform: phase=test
# conform: origin=tests/e2e/inherent_methods_test.go:14 TestInherentImplFaultFrame
type Counter:
    value: Int

impl Counter:
    def overflow() -> Int:
        return self.value * self.value

test "inherent fault frame":
    Counter(value: 9223372036854775807).overflow()
