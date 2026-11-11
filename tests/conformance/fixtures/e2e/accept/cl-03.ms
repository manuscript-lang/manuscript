// conform: tags=interpolation,modules,records,stdlib-testing,strings,testing,tier-core,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/cl-03.ms
import expect_equal from "@std/test/test.ms"

type CustomerId:
    value: String

type OrderId:
    value: String

type Customer:
    id: CustomerId
    name: String

fn customer_name(customer: Customer) String:
    {id: {value}, name: display_name} := customer
    return "{value}: {display_name}"

test "nominal record and nested binding":
    customer := Customer(CustomerId("c1"), "Ada")
    expect_equal(customer_name(customer), "c1: Ada")?
