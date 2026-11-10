// Receiver documentation.
type Meter:
    value: Int

impl Meter:
    // Method documentation.
    fn read() Int:
        return self.value

    fn plain() Int:
        return self.value

// Function documentation.
fn documented(value: Int) Int:
    return value + 123

fn caller(meter: Meter) Int:
    return documented(meter.read() + meter.plain())

fn unicode(value: Int) String:
    return "😀{value}"
