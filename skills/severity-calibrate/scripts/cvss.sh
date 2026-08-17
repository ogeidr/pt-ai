#!/bin/sh
# cvss.sh — compute CVSS v3.1 base + temporal score + severity band from a vector.
#
# Why this exists: severity-calibrate's whole job is honest, exact severity math.
# CVSS v3.1 is a closed formula, so it is computed here deterministically rather
# than by hand — no mental arithmetic, no rounding drift. Temporal metrics are
# optional; if E/RL/RC are absent they default to X (1.0) and temporal == base.
#
# Usage:
#   cvss.sh "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H[/E:U/RL:O/RC:C]"
# Output (tab-separated): BASE  TEMPORAL  SEVERITY
#
# $AWK pins the interpreter (default: whatever `awk` resolves to). The formula is
# plain POSIX awk, but implementations differ in float handling — CI uses this to
# assert the same scores under mawk and gawk.
[ -z "$1" ] && { echo "usage: cvss.sh <CVSS:3.1 vector>" >&2; exit 2; }
echo "$1" | ${AWK:-awk} -F/ '
function v(k){return M[k]}
function min(a,b){return a<b?a:b}
# CVSS v3.1 spec roundup: integer math on x*100000 avoids float drift.
function roundup(x,   ii){ ii=int(x*100000 + 0.5); if(ii % 10000 == 0) return ii/100000; return (int(ii/10000)+1)/10 }
function band(s){ if(s==0)return"info"; if(s<4)return"low"; if(s<7)return"medium"; if(s<9)return"high"; return"critical" }
{
  for(i=1;i<=NF;i++){split($i,p,":"); M[p[1]]=p[2]}
  av["N"]=0.85; av["A"]=0.62; av["L"]=0.55; av["P"]=0.2
  ac["L"]=0.77; ac["H"]=0.44
  ui["N"]=0.85; ui["R"]=0.62
  cia["N"]=0;   cia["L"]=0.22; cia["H"]=0.56
  scope=v("S")
  if(scope=="C"){pr["N"]=0.85; pr["L"]=0.68; pr["H"]=0.5}
  else          {pr["N"]=0.85; pr["L"]=0.62; pr["H"]=0.27}
  e["X"]=1;e["H"]=1;e["F"]=0.97;e["P"]=0.94;e["U"]=0.91
  rl["X"]=1;rl["U"]=1;rl["W"]=0.97;rl["T"]=0.96;rl["O"]=0.95
  rc["X"]=1;rc["C"]=1;rc["R"]=0.96;rc["U"]=0.92
  ISS = 1-(1-cia[v("C")])*(1-cia[v("I")])*(1-cia[v("A")])
  if(scope=="C") impact = 7.52*(ISS-0.029) - 3.25*((ISS-0.02)^15)
  else           impact = 6.42*ISS
  expl = 8.22*av[v("AV")]*ac[v("AC")]*pr[v("PR")]*ui[v("UI")]
  if(impact<=0) base=0
  else if(scope=="C") base=roundup(min(1.08*(impact+expl),10))
  else                base=roundup(min(impact+expl,10))
  E=(v("E")==""?1:e[v("E")]); RL=(v("RL")==""?1:rl[v("RL")]); RC=(v("RC")==""?1:rc[v("RC")])
  temp = roundup(base*E*RL*RC)
  printf "%.1f\t%.1f\t%s\n", base, temp, band(temp)
}'
