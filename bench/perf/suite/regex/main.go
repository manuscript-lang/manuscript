package main

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

func lcg(x int) int { return (x*1103515245 + 12345) % 2147483648 }

func makeText(lines int) string {
	var sb strings.Builder
	x := 9
	for i := 0; i < lines; i++ {
		x = lcg(x)
		fmt.Fprintf(&sb, "user%d@host%d.com 10.%d.%d.%d GET /api/v%d/items/%d %d took %dms\n",
			x%5000, x/3%90, x%256, x/5%256, x/7%256, x%4, x/11%100000, 200+x%3*100, x%900)
	}
	return sb.String()
}

func main() {
	text := makeText(120000)
	emails := regexp.MustCompile(`[a-z]+[0-9]*@[a-z]+[0-9]*\.com`)
	ips := regexp.MustCompile(`([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)`)
	times := regexp.MustCompile(`took ([0-9]+)ms`)
	versions := regexp.MustCompile(`/api/v[0-9]/`)

	emailCount := len(emails.FindAllString(text, -1))
	octets := 0
	for _, m := range ips.FindAllStringSubmatch(text, -1) {
		v, _ := strconv.Atoi(m[4])
		octets += v
	}
	took := 0
	for _, m := range times.FindAllStringSubmatch(text, -1) {
		v, _ := strconv.Atoi(m[1])
		took += v
	}
	masked := ips.ReplaceAllString(text, "x.x.x.x")
	versionsFound := len(versions.FindAllString(text, -1))
	pieces := len(regexp.MustCompile(` +`).Split(text, -1))
	fmt.Printf("emails %d octets %d took %d masked %d versions %d pieces %d\n", emailCount, octets, took, len(masked), versionsFound, pieces)
}
