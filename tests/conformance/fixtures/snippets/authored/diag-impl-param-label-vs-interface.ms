# conform: tags=diagnostics,interfaces,tier-core
# conform: phase=check
# conform: origin=type-checker bug bash
interface Comparable2:
    fn compare(other: Int) Int

type Ver:
    major: Int

impl Comparable2 for Ver:
    fn compare(o: Int) Int:
        return self.major - o

export fn main() Int:
    return 0
