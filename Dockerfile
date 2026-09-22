FROM debian:13-slim

LABEL maintainer="support@ip2location.com"

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y mariadb-server wget unzip \
	&& rm -rf /var/lib/apt/lists/*

ADD app/custom.cnf /etc/mysql/mariadb.conf.d/999-custom.cnf

ADD app/main.sh /main.sh
ADD app/update.sh /update.sh
ADD app/entrypoint.sh /entrypoint.sh
RUN chmod 755 /*.sh

VOLUME ["/var/lib/mysql"]

EXPOSE 3306 33060

ENTRYPOINT ["/entrypoint.sh"]
