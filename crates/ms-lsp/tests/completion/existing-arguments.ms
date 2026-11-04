fn trim_text(value: String) String:
    return value.trim()

fn receive[T](value: T) T:
    return value

fn generic() Int:
    return receive[Int](1)

fn continued(value: String) String:
    return (value.trim
        ())

fn commented(value: String) String:
    return (value.trim // note
        ())
