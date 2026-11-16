fn bad(value: (fn() Int)?) Void:
    operation := value.ok_or[Int]
