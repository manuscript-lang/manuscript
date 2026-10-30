export fn main() Int:
    var reserved = List[Int](reserve: 1000)
    if reserved.length() != 0: return 1

    for index in 0..2000:
        reserved.append(index)
    if reserved.length() != 2000 or reserved[1999] != 1999: return 2

    let negative = List[String](reserve: -5)
    if negative.length() != 0: return 3

    let absent: Int? = none
    if List[Int](reserve: absent).length() != 0: return 4

    return 0
