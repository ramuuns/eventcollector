FROM elixir:1.14.3

WORKDIR /var/www/eventcollector
ADD config.json /etc/eventcollector/config.json
ADD mix* ./
RUN mix do local.hex --force, local.rebar --force
RUN mix deps.get
ADD test test
ADD config config
ADD lib lib
RUN mix compile
ENTRYPOINT mix run --no-halt
