FROM elixir:1.14.3

WORKDIR /var/www/eventcollector
ADD config.json /etc/eventcollector/config.json
ADD mix* ./
RUN mix do local.hex --force, local.rebar --force && mix deps.get && mix deps.compile
ADD test test
ADD config config
ADD lib lib
RUN mix compile
ENTRYPOINT mix run --no-halt
