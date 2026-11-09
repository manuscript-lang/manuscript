fn change(r: List[Int]!) Unit:
    var xs = r.get()  // error: the result is a reference into more than one place
    xs.append(1)
