//go:build ignore

// gen prints reference results of Go's time package for the Timestamp operations of @std/time.
// Usage: go run gen.go [count] > golden.txt
package main

import (
	"fmt"
	"math/rand"
	"os"
	"strconv"
	"strings"
	"time"
	_ "time/tzdata"
)

func main() {
	n := 300
	if len(os.Args) > 1 {
		n, _ = strconv.Atoi(os.Args[1])
	}
	r := rand.New(rand.NewSource(11))
	zones := []string{"UTC", "", "+05:30", "-03:30", "+00:00", "America/New_York", "Europe/London", "Asia/Tokyo",
		"Australia/Sydney", "America/Sao_Paulo", "Asia/Kolkata", "Pacific/Auckland", "Africa/Cairo", "Europe/Moscow",
		"America/St_Johns", "Australia/Lord_Howe", "Etc/GMT+5", "US/Pacific", "Europe/Dublin", "Asia/Tehran", "Pacific/Apia"}
	for i := 0; i < n; i++ {
		var secs int64
		switch r.Intn(4) {
		case 0:
			secs = r.Int63n(4102444800-946684800) + 946684800 // 2000..2100
		case 1:
			secs = r.Int63n(946684800+2208988800) - 2208988800 + 0 // 1900..2000
		case 2:
			secs = r.Int63n(253402300799+62135596800) - 62135596800 // whole range
		default:
			secs = r.Int63n(86400*400) + 1704067200 - 86400*200 // around DST changes in 2024
		}
		nanos := int64(r.Intn(1000000000))
		zone := zones[r.Intn(len(zones))]
		loc, _ := loadZone(zone)
		t := time.Unix(secs, nanos).UTC().In(loc)
		name, off := t.Zone()
		fmt.Printf("cal %d %d %s => %d %d %d %d %d %d %d %d %d %d %s\n", secs, nanos, zone, t.Year(), int(t.Month()), t.Day(), t.Hour(), t.Minute(), t.Second(), t.Nanosecond(), int(t.Weekday()), t.YearDay(), off, strings.ReplaceAll(name, " ", "_"))
		fmt.Printf("str %d %d => %s\n", secs, nanos, time.Unix(secs, nanos).UTC().Format(time.RFC3339Nano))
		// Calendar round trip with strict validation as in Time_FromCalendar.
		y, mo, d := r.Intn(9999)+1, r.Intn(13), r.Intn(33)
		if r.Intn(2) == 0 {
			y, mo, d = 1990+r.Intn(60), r.Intn(12)+1, r.Intn(31)+1
		}
		h, mi, s, ns := r.Intn(25), r.Intn(61), r.Intn(61), r.Intn(1000000000)
		if r.Intn(2) == 0 {
			h, mi, s = r.Intn(24), r.Intn(60), r.Intn(60)
		}
		res := "ERR"
		if y >= 1 && y <= 9999 && mo >= 1 && mo <= 12 && d >= 1 && h >= 0 && h <= 23 && mi >= 0 && mi <= 59 && s >= 0 && s <= 59 {
			t := time.Date(y, time.Month(mo), d, h, mi, s, ns, loc)
			if t.Day() == d && int(t.Month()) == mo && t.UTC().Year() >= 1 && t.UTC().Year() <= 9999 {
				res = fmt.Sprintf("%d", t.Unix())
			}
		}
		fmt.Printf("from %d %d %d %d %d %d %d %s => %s\n", y, mo, d, h, mi, s, ns, zone, res)
	}
}

func loadZone(zone string) (*time.Location, bool) {
	switch zone {
	case "UTC", "":
		return time.UTC, true
	}
	if len(zone) == 6 && (zone[0] == '+' || zone[0] == '-') && zone[3] == ':' {
		seconds := (int(zone[1]-'0')*10+int(zone[2]-'0'))*3600 + (int(zone[4]-'0')*10+int(zone[5]-'0'))*60
		if zone[0] == '-' {
			seconds = -seconds
		}
		return time.FixedZone(zone, seconds), true
	}
	loc, err := time.LoadLocation(zone)
	return loc, err == nil
}
