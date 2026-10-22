# Debian 7 "wheezy" (gcc 4.7): old enough for PHP 5.2's code and configure checks.
# The image's libc comes from wheezy-security, so that archive is needed too.
FROM debian:wheezy
RUN printf '%s\n' \
      'deb http://archive.debian.org/debian wheezy main' \
      'deb http://archive.debian.org/debian-security wheezy/updates main' > /etc/apt/sources.list \
 && apt-get -o Acquire::Check-Valid-Until=false update \
 && apt-get install -y --force-yes --no-install-recommends build-essential file libxml2-dev ca-certificates re2c zlib1g-dev git \
 && rm -rf /var/lib/apt/lists/*
COPY ci52.sh /usr/local/bin/ci52.sh
RUN chmod +x /usr/local/bin/ci52.sh
