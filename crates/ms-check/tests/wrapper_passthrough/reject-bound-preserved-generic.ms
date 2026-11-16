fn bad[T](value: T?) Void:
    operation := value.ok_or[Int]
