// conform: tags=testing,tier-core
// conform: phase=check
export fn main() Int {
	return ["a", "b"].sum().length()
}
// expect-error: MS2001 4:23 unknown or ambiguous member sum on List[String]; sum requires String to be Numeric[Int, Int8, Int16, Int32, UInt8, UInt16, UInt32, Float, Float32]; String is not a member of the type set Numeric; its members are Int, Int8, Int16, Int32, UInt8, UInt16, UInt32, Float, Float32
