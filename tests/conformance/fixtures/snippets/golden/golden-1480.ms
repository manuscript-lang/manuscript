// conform: tags=diagnostics
// conform: phase=check
type Counter:
    value: Int

impl Counter:
    fn overflow() Int:
        return self.value * self.value

test "inherent fault frame":
    Counter(value: 9223372036854775807).overflow()
