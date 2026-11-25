// conform: tags=diagnostics,formatter,interfaces,tier-core,try-result
// conform: phase=check,parse
// conform: origin=documentation/core-language/types/contracts.md:10
interface Payments {
	fn charge(amount Money) Result[Receipt, PaymentError]
}
// expect-error: MS2001 5:22 unknown type Money; declare it with 'type Money:' / 'enum Money:' / 'interface Money:', declare it as a type parameter, or import it
// expect-error: MS2001 5:36 unknown type Receipt; declare it with 'type Receipt:' / 'enum Receipt:' / 'interface Receipt:', declare it as a type parameter, or import it
// expect-error: MS2001 5:45 unknown type PaymentError; declare it with 'type PaymentError:' / 'enum PaymentError:' / 'interface PaymentError:', declare it as a type parameter, or import it
