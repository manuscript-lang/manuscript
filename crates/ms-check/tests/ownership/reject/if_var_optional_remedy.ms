fn f(var value: List[Int]?) Unit:
    if var x = value:  // error: read the payload with `if x := value:`
        x.append(1)
