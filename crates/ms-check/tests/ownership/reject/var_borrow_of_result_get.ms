fn change(r: List[Int]!) Void:
    var xs = r.get()  // error: it borrows its receiver
    xs.append(1)
