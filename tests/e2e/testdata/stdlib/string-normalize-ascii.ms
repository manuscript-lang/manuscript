import expect_equal from "@std/test/test.ms"
import StringError from "@std/string.ms"

test "ASCII normalization is identical under every form and byte budget":
    let pattern = "aZ09\u{0}\t\n\u{7f}"

    for length in [0, 1, 2, 15, 16, 17, 31, 32, 128, 4096, 1048576]:
        let text = pattern.repeat((length + 7) / 8).get().slice_scalars(0, length).get()

        for form in ["NFC", "NFD", "NFKC", "NFKD"]:
            try expect_equal(text.normalize(form).get(), text.clone())
            try expect_equal(text.normalize(form, length).get(), text.clone())

            if length > 0:
                try expect_equal(
                    text.normalize(form, length - 1).err(), StringError.LimitExceeded
                )
                try expect_equal(
                    text.normalize(form, 0).err(), StringError.LimitExceeded
                )

            try expect_equal(text.normalize(form, -1).err(), StringError.InvalidInput)

test "normalization falls back for Unicode before and after long ASCII prefixes":
    for length in [0, 1, 4096, 1048576]:
        let ascii = "x".repeat(length).get()

        for form in ["NFC", "NFD", "NFKC", "NFKD"]:
            var expected = "e\u{301}fi"
            if form == "NFC": expected = "éﬁ"
            if form == "NFD": expected = "e\u{301}ﬁ"
            if form == "NFKC": expected = "éfi"
            try expect_equal(("éﬁ" + ascii).normalize(form).get(), expected + ascii)
            try expect_equal((ascii + "éﬁ").normalize(form).get(), ascii + expected)
