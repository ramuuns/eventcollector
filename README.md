# Eventcollector

A simple elixr Plug/Cowboy app that accepts json post requests to /event and does
aggregations of these events over pre-defined 1/15/60 minute periods and then creates
metrcis out of that and posts them to a graphite instance.

The configuration is stored in `/etc/eventcollector/config.json` 

# TODO

process more data from the events, potentially move the "what and how to process" into a config

