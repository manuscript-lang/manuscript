# conform: tags=formatter,parser,records,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/records.md:38
type Options:
    count: Int = 3
    total: Int = count + 1

let options = Options(count: 5)  # total defaults to 6
