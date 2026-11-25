// conform: tags=diagnostics
// conform: phase=check
type Counter {
    value Int
}

impl Counter {
    fn overflow() Int {
        return self.value * self.value
    }
}

test "inherent fault frame" {
    Counter(value: 9223372036854775807).overflow()
}
// expect-error: MS1000 7:1-7:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
