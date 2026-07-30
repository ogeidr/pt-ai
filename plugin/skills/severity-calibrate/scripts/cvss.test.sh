#!/bin/sh
# cvss.test.sh — assert cvss.sh against FIRST's published CVSS v3.1 reference
# scores (https://www.first.org/cvss/v3-1/examples). Resolves cvss.sh next to
# itself, so run it from this scripts/ directory:  sh cvss.test.sh
DIR=$(dirname "$0")
CVSS="$DIR/cvss.sh"
fail=0

# check <vector> <expected_base> <expected_temporal> <expected_band>
check() {
  got=$(sh "$CVSS" "$1")
  want="$2	$3	$4"
  if [ "$got" = "$want" ]; then
    printf "ok    %s -> %s\n" "$1" "$got"
  else
    printf "FAIL  %s\n        got:  %s\n        want: %s\n" "$1" "$got" "$want"
    fail=1
  fi
}

# base-score references
check "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H"  "9.8"  "9.8"  "critical"
check "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N"  "7.5"  "7.5"  "high"      # Heartbleed
check "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H"  "10.0" "10.0" "critical"  # scope-changed
check "CVSS:3.1/AV:L/AC:L/PR:L/UI:N/S:U/C:H/I:H/A:H"  "7.8"  "7.8"  "high"
check "CVSS:3.1/AV:L/AC:H/PR:H/UI:R/S:U/C:L/I:N/A:N"  "1.8"  "1.8"  "low"
check "CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:C/C:L/I:L/A:N"  "6.1"  "6.1"  "medium"    # scope-changed

# temporal deflation (base 9.8 with E:U RL:U RC:U -> 8.3, critical -> high)
check "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H/E:U/RL:U/RC:U"  "9.8"  "8.3"  "high"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
