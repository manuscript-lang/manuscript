# Guide

A fragment that does not type-check still gets linted:

```ms
x := match a {
    1 => match b {
        2 => 3
        _ => 4
    }
    _ => 5
}
```

A statement-only fragment:

```manuscript
if ready {
    value := match a {
        1 => match b {
            2 => 3
            _ => 4
        }
        _ => 5
    }
}
```

A flat match and a fixture that opts out with a reason pass:

```ms
fn f() Int {
    return match a {
        // manuscript:allow-nested-match shows the old spelling
        1 => match b {
            2 => 3
            _ => 4
        }
        _ => 5
    }
}
```
