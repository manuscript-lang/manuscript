export fn main() Int:
    var reserved = List[Int](reserve: 1000)
    if not reserved.is_empty(): return 1

    for index in 0..2000:
        reserved.append(index)
    if reserved.length() != 2000 or reserved[1999] != 1999: return 2

    negative := List[String](reserve: -5)
    if not negative.is_empty(): return 3

    absent: Int? := none
    if List[Int](reserve: absent).length() != 0: return 4

    return 0
