# conform: tags=formatter,interfaces,parser,records,testing,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/inherent_methods_test.go:14 TestInherentImplFaultFrame
type Counter:
    value: Int

impl Counter:
    fn overflow() Int:
        return self.value * self.value

test "inherent fault frame":
    Counter(value: 9223372036854775807).overflow()
