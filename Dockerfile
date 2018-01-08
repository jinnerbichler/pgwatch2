FROM ubuntu:16.04

RUN apt-get -q update \
    && apt-get -qy install wget apt-transport-https vim git supervisor postgresql postgresql-plpython-9.5 libfontconfig python3-pip \
    && locale-gen "en_US.UTF-8" && apt autoremove -y \
    && mkdir -p /var/log/supervisor /pgwatch2 \
    && rm -rf /var/lib/postgresql/9.5/main \
    && echo "include = 'pgwatch_postgresql.conf'" >> /etc/postgresql/9.5/main/postgresql.conf \
    && chgrp -R 0 /pgwatch2 /var/log/supervisor /etc/supervisor /var/run /var/lib/postgresql /var/log/postgresql /var/run/postgresql /etc/postgresql \
    && chmod -R g=u /pgwatch2 /var/log/supervisor /etc/supervisor /var/run /var/lib/postgresql /var/log/postgresql /etc/postgresql \
    && chmod g=u /etc/passwd

### Download and install external components
# Grafana [https://grafana.com/grafana/download]
#   latest ver.: curl -so- https://api.github.com/repos/grafana/grafana/tags | grep -Eo '"v[0-9\.]+"' | grep -Eo '[0-9\.]+' | sort -nr | head -1
# Influxdb [https://portal.influxdata.com/downloads]
#   latest ver.: curl -so- https://api.github.com/repos/influxdata/influxdb/tags | grep -Eo '"v[0-9\.]+"' | grep -Eo '[0-9\.]+' | sort -nr | head -1

RUN wget -q -O grafana.deb https://s3-us-west-2.amazonaws.com/grafana-releases/release/grafana_4.6.3_amd64.deb \
    && wget -q -O - https://dl.influxdata.com/influxdb/releases/influxdb_1.4.2_amd64.deb > influxdb_amd64.deb \
    && dpkg -i grafana.deb && rm grafana.deb \
    && mkdir -p /var/run/grafana \
    && chgrp -R 0 /etc/grafana/ /usr/share/grafana /var/lib/grafana /var/log/grafana /var/run/grafana \
    && chmod -R g=u /etc/grafana/ /usr/share/grafana /var/lib/grafana /var/log/grafana /var/run/grafana \
    && dpkg -i influxdb_amd64.deb && rm influxdb_amd64.deb \
    && chgrp -R 0 /var/lib/influxdb /var/log/influxdb /usr/lib/influxdb /etc/influxdb \
    && chmod -R g=u /var/lib/influxdb /var/log/influxdb /usr/lib/influxdb /etc/influxdb \
    && sed -i 's/\# query-log-enabled = true/query-log-enabled = false/' /etc/influxdb/influxdb.conf \
    && sed -i 's/\# \[monitor\]/\[monitor\]/' /etc/influxdb/influxdb.conf \
    && sed -i 's/\# store-enabled = true/store-enabled = false/' /etc/influxdb/influxdb.conf \
    && sed -i 's/\# \[http\]/\[http\]/' /etc/influxdb/influxdb.conf \
    && sed -i '0,/\# log-enabled = true/{s/\# log-enabled = true/log-enabled = false/}' /etc/influxdb/influxdb.conf

# Add pgwatch2 sources
ADD pgwatch2 /pgwatch2
ADD webpy /pgwatch2/webpy

# Go installation [https://golang.org/dl/]
# Grafana config customizations, Web UI requirements, compilation of the Go gatherer
RUN wget -q -O /tmp/go.tar.gz https://storage.googleapis.com/golang/go1.9.2.linux-amd64.tar.gz \
    && tar -C /usr/local -xzf /tmp/go.tar.gz \
    && export PATH=$PATH:/usr/local/go/bin \
    && cp /pgwatch2/bootstrap/grafana_custom_config.ini /etc/grafana/grafana.ini \
    && pip3 install -r /pgwatch2/webpy/requirements.txt \
    && cd /pgwatch2 && bash build_gatherer.sh \
    && rm /tmp/go.tar.gz \
    && rm -rf /usr/local/go \
    && chgrp -R 0 /pgwatch2/webpy \
    && chmod -R g=u /pgwatch2/webpy

ADD grafana_dashboards /pgwatch2/grafana_dashboards

# For showing all component versions via :8080/versions. Assuming project is cloned from Github here
COPY .git/refs/heads/master /pgwatch2/build_git_version.txt

# Set up supervisord [https://docs.docker.com/engine/admin/using_supervisord/]
COPY supervisord.conf /etc/supervisor/supervisord.conf

# Postgres (ver 9.5) config tuning
# NB! When security is a concern one should definitely alter "pgwatch2" password in change_pw.sql and maybe modify pg_hba.conf accordingly
COPY postgresql.conf /etc/postgresql/9.5/main/pgwatch_postgresql.conf
COPY pg_hba.conf /etc/postgresql/9.5/main/pg_hba.conf
COPY docker-launcher.sh /pgwatch2/


# Admin UI for configuring servers to be monitored
EXPOSE 8080
# Postgres DB holding the pgwatch2 config DB
EXPOSE 5432
# Grafana UI
EXPOSE 3000
# InfluxDB API
EXPOSE 8086
# InfluxDB backup port
EXPOSE 8088

###
### OpenShift compatibility - run all using an unprivileged user:
### https://docs.openshift.org/latest/creating_images/guidelines.html#openshift-specific-guidelines
###

USER 10001

CMD ["/pgwatch2/docker-launcher.sh"]
