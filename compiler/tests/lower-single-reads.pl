# Reads the keyed lowering text on stdin (one function per line, newlines written as `\n`).
# Rust reads a field twice when it clones it (`self.name.clone()`): two identical `type.get` in a row,
# the first never used. C reads it once. This drops the unused first read and renumbers the values after it.
use strict;
use warnings;

while (my $line = <STDIN>) {
    chomp $line;
    while ($line =~ /%(\d+): (\S+) = type\.get (\S+) %(\d+) (!\S+)\\n  %(\d+): \2 = type\.get \3 %\4 \5\\n/g) {
        my ($first, $second, $start, $end) = ($1, $6, $-[0], $+[0]);
        next unless $second == $first + 1;
        my $both = substr($line, $start, $end - $start);
        (my $kept = $both) =~ s/^[^\\]*\\n  //;
        my $tail = substr($line, $end);
        next if $tail =~ /%$first(?!\d)/; # the first read is used after all
        $tail =~ s/%(\d+)/"%" . ($1 > $first ? $1 - 1 : $1)/ge;
        $kept =~ s/^%(\d+)/"%" . ($1 - 1)/e;
        $line = substr($line, 0, $start) . $kept . $tail;
        pos($line) = $start;
    }
    print "$line\n";
}
