docker-ip2proxy-mysql
=====================

A ready-to-run MySQL server preloaded with an [IP2Proxy](https://www.ip2location.com/database/ip2proxy) proxy IP database. Supports the commercial packages and the free [LITE](https://lite.ip2location.com) package. Register for an account first as download token is required.



## Usage

```bash
docker network create ip2proxy-network

docker run --name ip2proxy \
  --network ip2proxy-network \
  -d \
  -e TOKEN={DOWNLOAD_TOKEN} \
  -e CODE={DOWNLOAD_CODE} \
  -e IP_TYPE=IPV4 \
  -e MYSQL_PASSWORD={MYSQL_PASSWORD} \
  ip2proxy/mysql

docker logs -f ip2proxy      # Wait for "✓ Setup completed"
```

**ENV Variables**

| Variable | Description |
|---|---|
| `TOKEN` | Download token. Required. |
| `CODE` | Database code. Required. See below. |
| `IP_TYPE` | `IPV4` (default) or `IPV6`. |
| `MYSQL_PASSWORD` | Password for the `admin` user. Random if omitted. |

**`CODE`** — Free Database: `PX1-LITE`, `PX2-LITE`, `PX3-LITE`, `PX4-LITE`, `PX5-LITE`, `PX6-LITE`, `PX7-LITE`, `PX8-LITE`, `PX9-LITE`, `PX10-LITE`, `PX11-LITE`, `PX12-LITE`.
Commercial Database: `PX1`, `PX2`, `PX3`, `PX4`, `PX5`, `PX6`, `PX7`, `PX8`, `PX9`, `PX10`, `PX11`, `PX12`.

Only one address family is installed per container. To switch, start a fresh container with an empty `/var/lib/mysql` — an existing install is not converted in place, and re-running with different settings prints a note explaining that.

The admin password is written to `/ip2proxy.conf` inside the container, so `docker logs` and `docker exec` access are equivalent to knowing it.

To start over:

```bash
docker rm -f ip2proxy
docker volume rm ip2proxy-data        # if you used -v ip2proxy-data:/var/lib/mysql
```



## Query for IP Information

The table stores each entry as an `ip_from`/`ip_to` number range. A built-in `IP_ATON()` converts an address to that number, so you can query with the address directly:

```sql
SELECT * FROM `ip2proxy_database` WHERE IP_ATON('8.8.8.8') BETWEEN ip_from AND ip_to LIMIT 1;
```

**Both bounds are required.** The database lists only addresses that have proxy data, so the ranges are sparse: they do not cover the address space and most addresses sit in a gap between two ranges. Matching on `ip_to` alone (`IP_ATON('8.8.8.8') <= ip_to LIMIT 1`) matches millions of rows, and with no `ORDER BY` the row you get back is an arbitrary one of those — so it reports a proxy record for an address that is not a proxy. `BETWEEN ip_from AND ip_to` matches the single range that actually contains the address, or nothing.

`IP_ATON()` handles both IPv4 and IPv6, so the same query works whichever `IP_TYPE` you installed. It is created during setup.

No row returned means the address is not in the database. For IP2Proxy that is the ordinary result for most addresses, since only a small share of the address space carries proxy data.



## Connect from an Application

Put your application on the same network and reach the container by name (`ip2proxy`):

```bash
docker run --network ip2proxy-network -t -i {YOUR_APPLICATION}
```

The client binary is `mariadb`, not `mysql`.



## Update IP2Proxy Database

```bash
docker exec -it ip2proxy /update.sh
```

Downloads a fresh copy and swaps it in, so queries keep working against the old data until the swap. The daily download quota is limited. If you get `[QUOTA EXCEEDED]` error, please try again after 24 hours.



## Articles and Tutorials

[IP2Proxy Articles and Tutorials](https://blog.ip2location.com)
