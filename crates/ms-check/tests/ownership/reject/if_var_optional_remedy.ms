fn f(var value: List[Int]?) Void:
    if var x = value:  // error: read the payload with `if x := value:`
        x.append(1)
