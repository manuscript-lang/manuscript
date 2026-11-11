import other from "./other.ms"

type Box:
    value: Int

fn Box.read() Int:
    return self.value

type Item:
    value: Int

type Named:
    value: Int

fn unique() Int:
    return 1

test "main.ms#record#Box":
    _value := 1

test "other.ms::Named":
    _value := 1
