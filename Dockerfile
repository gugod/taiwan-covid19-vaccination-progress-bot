FROM docker.io/library/perl:5.36

WORKDIR /app
COPY . /app
RUN cpanm --notest --quiet App::cpm && \
    cpm install --show-build-log-on-failure -g && \
    rm -rf /root/.perl-cpm /root/.cpanm
