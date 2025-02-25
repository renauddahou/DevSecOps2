FROM debian:wheezy

LABEL maintainer "dyakimov@swordfishseucrity.com"

# Packages
COPY apt/sources.wheezy      /etc/apt/sources.list
COPY apt/preferences.wheezy  /etc/apt/preferences.d/preferences
COPY apt/conf.archive.wheezy /etc/apt/apt.conf.d/archive

RUN apt-get update && \
    apt-get upgrade -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    apache2 \
    wget \
    python \
    sudo \
    curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN wget https://bootstrap.pypa.io/get-pip.py && \
    python get-pip.py

COPY packages /packages
COPY index.html /var/www
COPY webpage-img.jpg /var/www

RUN dpkg -i /packages/*

COPY vulnerable /usr/lib/cgi-bin/

RUN chown www-data:www-data /var/www/index.html

RUN echo 'www-data ALL=(ALL) NOPASSWD: /var/www/, /usr/local/bin/pip install *' >> /etc/sudoers

EXPOSE 80

COPY main.sh /

ENTRYPOINT ["/main.sh"]
CMD ["default"]


