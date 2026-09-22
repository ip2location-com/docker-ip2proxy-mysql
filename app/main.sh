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

USER_AGENT="Mozilla/5.0+(compatible; IP2Proxy/MySQL-Docker; https://hub.docker.com/r/ip2proxy/mysql)"
CODES=(PX1-LITE PX2-LITE PX3-LITE PX4-LITE PX5-LITE PX6-LITE PX7-LITE PX8-LITE PX9-LITE PX10-LITE PX11-LITE PX12-LITE PX1 PX2 PX3 PX4 PX5 PX6 PX7 PX8 PX9 PX10 PX11 PX12)

trim() { local v="${1//$'\r'/}"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"; printf '%s' "$v"; }

TOKEN="$(trim "$TOKEN")"
CODE="$(trim "$CODE")"
IP_TYPE="$(trim "$IP_TYPE")"
CODE_INPUT="$CODE"
if [ -f /ip2proxy.conf ]; then
	CONF_TOKEN="$(grep '^TOKEN=' /ip2proxy.conf | cut -d= -f2-)"
	CONF_CODE="$(grep '^CODE=' /ip2proxy.conf | cut -d= -f2-)"
	CONF_IP_TYPE="$(grep '^IP_TYPE=' /ip2proxy.conf | cut -d= -f2-)"
	CONF_PASSWORD="$(grep '^MYSQL_PASSWORD=' /ip2proxy.conf | cut -d= -f2-)"

	if [ -n "$CODE_INPUT" ] && [ "$CODE_INPUT" != "$CONF_CODE" ]; then
		echo " > NOTE: CODE has changed from '$CONF_CODE' to '$CODE_INPUT', but the database"
		echo " >       is already installed. The existing data is kept. To install"
		echo " >       '$CODE_INPUT' instead, start a fresh container with an empty /var/lib/mysql."
	fi
	if [ -n "$TOKEN" ] && [ "$TOKEN" != "$CONF_TOKEN" ]; then
		echo " > NOTE: TOKEN has changed but is not re-applied to an existing install."
	fi
	if [ -n "$IP_TYPE" ] && [ "$IP_TYPE" != "$CONF_IP_TYPE" ]; then
		echo " > NOTE: IP_TYPE has changed from '$CONF_IP_TYPE' to '$IP_TYPE', but the"
		echo " >       database is already installed and is not converted in place."
		echo " >       To install '$IP_TYPE', start a fresh container with an empty /var/lib/mysql."
		echo " >       Running ./update.sh keeps '$CONF_IP_TYPE'."
	fi
	if [ -n "$MYSQL_PASSWORD" ] && [ "$MYSQL_PASSWORD" != "$CONF_PASSWORD" ]; then
		echo " > NOTE: MYSQL_PASSWORD has changed but the existing admin password is kept."
		echo " >       Change it with: mariadb -e \"SET PASSWORD FOR 'admin'@'%' = PASSWORD('...')\""
	fi

	/etc/init.d/mariadb restart >/dev/null 2>&1
	tail -f /dev/null
fi

[ -z "$TOKEN" ] && fail "Missing download token. Pass it with -e TOKEN=..."
[ -z "$CODE" ] && fail "Missing database code. Pass it with -e CODE=... (e.g. PX1-LITE)"

if [ -z "$MYSQL_PASSWORD" ]; then
	MYSQL_PASSWORD="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-12})"
fi

FOUND=""
for i in "${CODES[@]}"; do
	if [ "$i" == "$CODE" ] ; then
		FOUND="$CODE"
	fi
done

if [ -z "$FOUND" ]; then
	fail "Download code '$CODE' is invalid. See the README for the list of supported codes."
fi

CODE=$(echo $CODE | sed 's/-//')

if [ "$IP_TYPE" == "IPV6" ]; then
	IP_TYPE="IPV6"
	SUFFIX="CSVIPV6"
else
	[ -n "$IP_TYPE" ] && [ "$IP_TYPE" != "IPV4" ] && echo " > IP_TYPE '$IP_TYPE' is not recognised, using IPV4."
	IP_TYPE="IPV4"
	SUFFIX="CSV"
fi

banner "IP2Proxy Database Setup"
field "Database" "ip2proxy_database"
field "Code" "$CODE_INPUT"
field "IP type" "$IP_TYPE"
echo ""

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

/etc/init.d/mariadb start > /dev/null 2>&1

step "Create database \"ip2proxy_database\""
RESPONSE="$(mariadb -e 'CREATE DATABASE IF NOT EXISTS ip2proxy_database' 2>&1)"

[ ! -z "$(echo $RESPONSE)" ] && fail "$RESPONSE" || ok

step "Create table \"ip2proxy_database_tmp\""
RESPONSE="$(mariadb ip2proxy_database -e 'DROP TABLE IF EXISTS ip2proxy_database_tmp' 2>&1)"

case "$CODE" in
	PX1|PX1LITE )
		FIELDS=',`country_code` CHAR(2) NOT NULL,`country_name` VARCHAR(64) NOT NULL'
	;;

	PX2|PX2LITE )
		FIELDS=',`proxy_type` VARCHAR(3) NOT NULL, `country_code` CHAR(2) NOT NULL,`country_name` VARCHAR(64) NOT NULL'
	;;

	PX3|PX3LITE )
		FIELDS=',`proxy_type` VARCHAR(3) NOT NULL, `country_code` CHAR(2) NOT NULL,`country_name` VARCHAR(64) NOT NULL,`region_name` VARCHAR(128) NOT NULL,`city_name` VARCHAR(128) NOT NULL'
	;;

	PX4|PX4LITE )
		FIELDS=',`proxy_type` VARCHAR(3) NOT NULL, `country_code` CHAR(2) NOT NULL,`country_name` VARCHAR(64) NOT NULL,`region_name` VARCHAR(128) NOT NULL,`city_name` VARCHAR(128) NOT NULL,`isp` VARCHAR(255) NOT NULL'
	;;

	PX5|PX5LITE )
		FIELDS=',`proxy_type` VARCHAR(3) NOT NULL, `country_code` CHAR(2) NOT NULL,`country_name` VARCHAR(64) NOT NULL,`region_name` VARCHAR(128) NOT NULL,`city_name` VARCHAR(128) NOT NULL,`isp` VARCHAR(255) NOT NULL,`domain` VARCHAR(128) NOT NULL'
	;;

	PX6|PX6LITE )
		FIELDS=',`proxy_type` VARCHAR(3) NOT NULL, `country_code` CHAR(2) NOT NULL,`country_name` VARCHAR(64) NOT NULL,`region_name` VARCHAR(128) NOT NULL,`city_name` VARCHAR(128) NOT NULL,`isp` VARCHAR(255) NOT NULL,`domain` VARCHAR(128) NOT NULL,`usage_type` VARCHAR(11) NOT NULL'
	;;

	PX7|PX7LITE )
		FIELDS=',`proxy_type` VARCHAR(3) NOT NULL, `country_code` CHAR(2) NOT NULL,`country_name` VARCHAR(64) NOT NULL,`region_name` VARCHAR(128) NOT NULL,`city_name` VARCHAR(128) NOT NULL,`isp` VARCHAR(255) NOT NULL,`domain` VARCHAR(128) NOT NULL,`usage_type` VARCHAR(11) NOT NULL,`asn` VARCHAR(6) NOT NULL,`as` VARCHAR(256) NOT NULL'
	;;

	PX8|PX8LITE )
		FIELDS=',`proxy_type` VARCHAR(3) NOT NULL, `country_code` CHAR(2) NOT NULL,`country_name` VARCHAR(64) NOT NULL,`region_name` VARCHAR(128) NOT NULL,`city_name` VARCHAR(128) NOT NULL,`isp` VARCHAR(255) NOT NULL,`domain` VARCHAR(128) NOT NULL,`usage_type` VARCHAR(11) NOT NULL,`asn` VARCHAR(6) NOT NULL,`as` VARCHAR(256) NOT NULL,`last_seen` INT(10) NOT NULL'
	;;

	PX9|PX9LITE )
		FIELDS=',`proxy_type` VARCHAR(3) NOT NULL, `country_code` CHAR(2) NOT NULL,`country_name` VARCHAR(64) NOT NULL,`region_name` VARCHAR(128) NOT NULL,`city_name` VARCHAR(128) NOT NULL,`isp` VARCHAR(255) NOT NULL,`domain` VARCHAR(128) NOT NULL,`usage_type` VARCHAR(11) NOT NULL,`asn` VARCHAR(6) NOT NULL,`as` VARCHAR(256) NOT NULL,`last_seen` INT(10) NOT NULL, `threat` VARCHAR(128)'
	;;

	PX10|PX10LITE )
		FIELDS=',`proxy_type` VARCHAR(3) NOT NULL, `country_code` CHAR(2) NOT NULL,`country_name` VARCHAR(64) NOT NULL,`region_name` VARCHAR(128) NOT NULL,`city_name` VARCHAR(128) NOT NULL,`isp` VARCHAR(255) NOT NULL,`domain` VARCHAR(128) NOT NULL,`usage_type` VARCHAR(11) NOT NULL,`asn` VARCHAR(6) NOT NULL,`as` VARCHAR(256) NOT NULL,`last_seen` INT(10) NOT NULL, `threat` VARCHAR(128)'
	;;

	PX11|PX11LITE )
		FIELDS=',`proxy_type` VARCHAR(3) NOT NULL, `country_code` CHAR(2) NOT NULL,`country_name` VARCHAR(64) NOT NULL,`region_name` VARCHAR(128) NOT NULL,`city_name` VARCHAR(128) NOT NULL,`isp` VARCHAR(255) NOT NULL,`domain` VARCHAR(128) NOT NULL,`usage_type` VARCHAR(11) NOT NULL,`asn` VARCHAR(6) NOT NULL,`as` VARCHAR(256) NOT NULL,`last_seen` INT(10) NOT NULL, `threat` VARCHAR(128),`provider` VARCHAR(256) NOT NULL'
	;;

	PX12|PX12LITE )
		FIELDS=',`proxy_type` VARCHAR(3) NOT NULL, `country_code` CHAR(2) NOT NULL,`country_name` VARCHAR(64) NOT NULL,`region_name` VARCHAR(128) NOT NULL,`city_name` VARCHAR(128) NOT NULL,`isp` VARCHAR(255) NOT NULL,`domain` VARCHAR(128) NOT NULL,`usage_type` VARCHAR(11) NOT NULL,`asn` VARCHAR(6) NOT NULL,`as` VARCHAR(256) NOT NULL,`last_seen` INT(10) NOT NULL, `threat` VARCHAR(128),`provider` VARCHAR(256) NOT NULL, `fraud_score` INT(10) NOT NULL'
	;;
esac

RESPONSE="$(mariadb ip2proxy_database -e 'DROP TABLE IF EXISTS ip2proxy_database_tmp' 2>&1)"

[ ! -z "$(echo $RESPONSE)" ] && fail "$RESPONSE"

RESPONSE="$(mariadb ip2proxy_database -e 'CREATE TABLE ip2proxy_database_tmp (`ip_from` DECIMAL(39,0) UNSIGNED NOT NULL,`ip_to` DECIMAL(39,0) UNSIGNED NOT NULL'"$FIELDS"',INDEX `idx_ip_to` (`ip_to`)) ENGINE=MyISAM' 2>&1)"

[ ! -z "$(echo $RESPONSE)" ] && fail "$RESPONSE" || ok

step "Load the CSV into the database"
RESPONSE="$(mariadb ip2proxy_database -e 'LOAD DATA LOCAL INFILE '\'''$CSV''\'' INTO TABLE ip2proxy_database_tmp FIELDS TERMINATED BY '\'','\'' ENCLOSED BY '\''\"'\'' LINES TERMINATED BY '\''\n'\''' 2>&1)"
[ ! -z "$(echo $RESPONSE)" ] && fail "$RESPONSE" || ok

step "Drop table \"ip2proxy_database\""

RESPONSE="$(mariadb ip2proxy_database -e 'DROP TABLE IF EXISTS ip2proxy_database' 2>&1)"

[ ! -z "$(echo $RESPONSE)" ] && fail "$RESPONSE" || ok

step "Activate ip2proxy_database"
RESPONSE="$(mariadb ip2proxy_database -e 'RENAME TABLE ip2proxy_database_tmp TO ip2proxy_database' 2>&1)"

[ ! -z "$(echo $RESPONSE)" ] && fail "$RESPONSE" || ok

step "Create user \"admin\""

mariadb -e "CREATE USER admin@'%' IDENTIFIED BY '$MYSQL_PASSWORD'" > /dev/null 2>&1
mariadb -e "GRANT ALL PRIVILEGES ON *.* TO admin@'%' WITH GRANT OPTION" > /dev/null 2>&1

ok

step "Create function \"IP_ATON\""

mariadb ip2proxy_database << 'SQL' > /dev/null 2>&1
DROP FUNCTION IF EXISTS IP_ATON;
DELIMITER $$
CREATE FUNCTION IP_ATON(ip VARCHAR(45)) RETURNS DECIMAL(39,0) DETERMINISTIC
BEGIN
	IF INET6_ATON(ip) IS NULL THEN RETURN NULL; END IF;
	IF IS_IPV6(ip) THEN
		RETURN CAST(CONV(HEX(SUBSTR(INET6_ATON(ip),1,8)),16,10) AS DECIMAL(39,0))
			* CAST(18446744073709551616 AS DECIMAL(39,0))
			+ CAST(CONV(HEX(SUBSTR(INET6_ATON(ip),9,8)),16,10) AS DECIMAL(39,0));
	END IF;
	RETURN CONV(HEX(INET6_ATON(ip)),16,10);
END$$
DELIMITER ;
SQL

RESPONSE="$(mariadb ip2proxy_database -e 'SELECT IP_ATON("8.8.8.8")' -N 2>&1)"

[ "$RESPONSE" == "134744072" ] && ok || fail "$RESPONSE"

banner "IP2Proxy Database Ready"
ROWS="$(mariadb ip2proxy_database -N -e 'SELECT COUNT(*) FROM ip2proxy_database' 2>/dev/null)"
summary "Setup completed" "$(group "$ROWS") records loaded from $CODE_INPUT ($IP_TYPE)"
field "Host" "ip2proxy"
field "Database" "ip2proxy_database"
field "User" "admin"
field "Password" "$MYSQL_PASSWORD"
printf '\n  %smariadb -h ip2proxy -u admin --password="%s" ip2proxy_database%s\n' "$C_DIM" "$MYSQL_PASSWORD" "$C_RESET"
note "Connection details are also stored in /ip2proxy.conf inside the container."
printf '\n'

echo "MYSQL_PASSWORD=$MYSQL_PASSWORD" > /ip2proxy.conf
echo "TOKEN=$TOKEN" >> /ip2proxy.conf
echo "CODE=$CODE_INPUT" >> /ip2proxy.conf
echo "IP_TYPE=$IP_TYPE" >> /ip2proxy.conf

rm -rf /_tmp

tail -f /dev/null
