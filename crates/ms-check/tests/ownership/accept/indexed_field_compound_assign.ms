type P:
    x: Int

def bump(var rows: List[P], i: Int) -> Unit:
    rows[0].x += 1
    rows[i].x *= 2
