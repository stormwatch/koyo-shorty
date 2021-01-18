FROM racket/racket:7.9-cs-full AS build

WORKDIR /opt/shorty
COPY .git /opt/shorty/.git
COPY ci /opt/shorty/ci
COPY shorty /opt/shorty/shorty
COPY migrations /opt/shorty/migrations
COPY resources /opt/shorty/resources
COPY static /opt/shorty/static

RUN ci/setup-catalogs.sh
RUN raco pkg install -D --auto --batch shorty/
RUN raco koyo dist ++lang north


FROM debian:bullseye-slim

COPY --from=build /opt/shorty/dist /opt/shorty

RUN apt-get update \
  && apt-get install -y --no-install-recommends dumb-init libargon2-1 libssl-dev \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

CMD ["dumb-init", "/opt/shorty/bin/shorty"]
