fn main() Void:
    data := "hi".to_bytes()
    print(data.to_string())
    n := 5
    print(n.to_string())
    print(data.decode_utf8().get_or(""))
