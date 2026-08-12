FROM debian:13-slim

LABEL maintainer="support@ip2location.com"

# Install packages
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y mariadb-server wget unzip

# Add MySQL configuration
ADD custom.cnf /etc/mysql/mariadb.conf.d/999-custom.cnf

# Add scripts
ADD run.sh /run.sh
ADD update.sh /update.sh
RUN chmod 755 /*.sh

# Add VOLUMEs
VOLUME  ["/etc/mysql", "/var/lib/mysql"]

EXPOSE 3306 33060
CMD ["bash", "/run.sh"]