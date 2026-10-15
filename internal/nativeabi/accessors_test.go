package nativeabi

import "testing"

func TestAccessorCategoriesCoverApprovedInventory(t *testing.T) {
	count := 0
	for receiver, members := range ReceiverAccessors {
		for name, accessor := range members {
			if !accessor {
				t.Fatalf("non-accessor entry %s.%s", receiver, name)
			}
			count++
			if name == "message" {
				t.Fatal("Error.message must remain a method")
			}
		}
	}
	if count != 59 {
		t.Fatalf("approved 56 migrations + 3 existing Int properties, got %d", count)
	}
	for _, name := range []string{"nanoseconds", "microseconds", "milliseconds", "seconds", "minutes", "hours"} {
		if ReceiverBindings["Duration"][name] != "time/duration_"+name || ReceiverBindings["Duration"]["to_"+name] != "" {
			t.Fatalf("Duration.%s binding identity/public spelling", name)
		}
	}
	for _, name := range []string{"milliseconds", "seconds", "minutes"} {
		if ReceiverBindings["Int"][name] != "time/int_"+name {
			t.Fatalf("Int.%s binding identity", name)
		}
	}
	if IsAccessor("BlockingQueue", "length") || IsAccessor("BlockingQueue", "is_closed") || IsAccessor("IpAddress", "text") || IsAccessor("Error", "message") || IsAccessor("List", "clone") || IsAccessor("List", "keys") {
		t.Fatal("migration exceeded approved inventory")
	}
}
