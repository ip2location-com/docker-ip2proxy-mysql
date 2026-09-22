#!/bin/bash

if [ -n "$NO_COLOR" ]; then
	C_RESET=; C_DIM=; C_BOLD=; C_OK=; C_WARN=; C_ERR=
else
	C_RESET=$'\e[0m'; C_DIM=$'\e[2m'; C_BOLD=$'\e[1m'
	C_OK=$'\e[32m'; C_WARN=$'\e[33m'; C_ERR=$'\e[31m'
fi

STEP_N=0
STEP_WIDTH=58

banner() {
	printf '\n%s  %s%s\n%s  %s%s\n\n' \
		"$C_BOLD" "$1" "$C_RESET" \
		"$C_DIM" "$(printf '─%.0s' $(seq 1 $((${#1} + 2))))" "$C_RESET"
}

step() {
	STEP_N=$((STEP_N + 1))
	printf '  %s%2d.%s ' "$C_DIM" "$STEP_N" "$C_RESET"
	local label="$1"
	[ ${#label} -gt "$STEP_WIDTH" ] && label="${label:0:$((STEP_WIDTH - 3))}..."

	local pad=$((STEP_WIDTH - ${#label})) dots=""
	[ $pad -gt 0 ] && dots="$(printf '·%.0s' $(seq 1 $pad))"

	local pad=$((STEP_WIDTH - ${#label})) dots=""
	[ $pad -gt 0 ] && dots="$(printf '·%.0s' $(seq 1 $pad))"

	printf '%s %s%s%s ' "$label" "$C_DIM" "$dots" "$C_RESET"
	printf '%s' "$C_DIM"
}
ok()   { if [ -n "$1" ]; then printf '%s✓%s %s(%s)%s\n' "$C_OK" "$C_RESET" "$C_DIM" "$1" "$C_RESET"; else printf '%s✓%s\n' "$C_OK" "$C_RESET"; fi; }
warn() { printf '%s!%s %s%s%s\n' "$C_WARN" "$C_RESET" "$C_DIM" "$1" "$C_RESET"; }
fail() { printf '%s✗%s %s\n' "$C_ERR" "$C_RESET" "$1"; exit 1; }

note()  { printf '     %s%s%s\n' "$C_DIM" "$1" "$C_RESET"; }
field() { printf '  %s%-9s%s %s\n' "$C_DIM" "$1" "$C_RESET" "$2"; }

group() {
	local n="$1" out=""
	while [ ${#n} -gt 3 ]; do
		out=",${n: -3}${out}"
		n="${n:0:${#n}-3}"
	done
	printf '%s%s' "$n" "$out"
}

summary() {
	printf '\n  %s✓%s %s%s%s\n' "$C_OK" "$C_RESET" "$C_BOLD$C_OK" "$1" "$C_RESET"
	[ -n "$2" ] && printf '    %s%s%s\n' "$C_DIM" "$2" "$C_RESET"
	printf '\n'
}

[ ! -f /ip2proxy.conf ] && fail "Missing configuration file."

banner "IP2Proxy Database Update"

USER_AGENT="Mozilla/5.0+(compatible; IP2Proxy/MySQL-Docker; https://hub.docker.com/r/ip2proxy/mysql)"
TOKEN=$(grep '^TOKEN=' /ip2proxy.conf | cut -d= -f2-)
CODE=$(grep '^CODE=' /ip2proxy.conf | cut -d= -f2-)
CODE_INPUT="$CODE"
IP_TYPE=$(grep '^IP_TYPE=' /ip2proxy.conf | cut -d= -f2-)
MYSQL_PASSWORD=$(grep '^MYSQL_PASSWORD=' /ip2proxy.conf | cut -d= -f2-)

CODE=$(echo $CODE | sed 's/-//')

if [ "$IP_TYPE" == "IPV6" ]; then
	IP_TYPE="IPV6"
	SUFFIX="CSVIPV6"
else
	IP_TYPE="IPV4"
	SUFFIX="CSV"
fi

rm -rf /_tmp && mkdir /_tmp && cd /_tmp

step "Download IP2Proxy $IP_TYPE database"

ARCHIVE="/_tmp/database.zip"
wget -O "$ARCHIVE" -q --user-agent="$USER_AGENT" "https://www.ip2location.com/download?token=${TOKEN}&code=${CODE}${SUFFIX}" > /dev/null 2>&1

[ ! -z "$(grep 'NO PERMISSION' "$ARCHIVE")" ] && fail "DENIED"
[ ! -z "$(grep '5 TIMES' "$ARCHIVE")" ] && fail "QUOTA EXCEEDED"

unzip -t "$ARCHIVE" >/dev/null 2>&1

[ $? -ne 0 ] && fail "FILE CORRUPTED"

ok

CSV=$(unzip -l "$ARCHIVE" | sort -nr | grep -Eio 'IP(V6)?.*CSV' | head -n 1)

step "Decompress the downloaded archive"

unzip -oq "$ARCHIVE" "$CSV"

if [ ! -f "/_tmp/$CSV" ]; then
	fail "ERROR"
fi

ok

step "Create table \"ip2proxy_database_tmp\""

RESPONSE="$(mariadb ip2proxy_database -e 'DROP TABLE IF EXISTS ip2proxy_database_tmp; CREATE TABLE ip2proxy_database_tmp LIKE ip2proxy_database' 2>&1)"

[ ! -z "$(echo $RESPONSE)" ] && fail "$RESPONSE" || ok

step "Load the CSV into the database"
RESPONSE="$(mariadb ip2proxy_database -e 'LOAD DATA LOCAL INFILE '\'''$CSV''\'' INTO TABLE ip2proxy_database_tmp FIELDS TERMINATED BY '\'','\'' ENCLOSED BY '\''\"'\'' LINES TERMINATED BY '\''\n'\''' 2>&1)"
[ ! -z "$(echo $RESPONSE)" ] && fail "$RESPONSE" || ok

step "Retire the previous table"

RESPONSE="$(mariadb ip2proxy_database -e 'RENAME TABLE ip2proxy_database TO ip2proxy_database_drop' 2>&1)"

[ ! -z "$(echo $RESPONSE)" ] && fail "$RESPONSE" || ok

step "Activate ip2proxy_database"

RESPONSE="$(mariadb ip2proxy_database -e 'RENAME TABLE ip2proxy_database_tmp TO ip2proxy_database' 2>&1)"

[ ! -z "$(echo $RESPONSE)" ] && fail "$RESPONSE" || ok

step "Drop table \"ip2proxy_database_drop\""

RESPONSE="$(mariadb ip2proxy_database -e 'DROP TABLE IF EXISTS ip2proxy_database_drop' 2>&1)"

[ ! -z "$(echo $RESPONSE)" ] && fail "$RESPONSE" || ok

rm -rf /_tmp

summary "Update completed" "$CODE_INPUT ($IP_TYPE) refreshed"
field "Database" "ip2proxy_database"
note "The previous data was dropped only after the new table finished loading."
printf '\n'
