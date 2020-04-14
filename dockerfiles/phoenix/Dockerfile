FROM h3poteto/elixir:1.10.2-slim-buster

USER root
ENV APP_DIR /var/opt/app
ADD . ${APP_DIR}
RUN chown -R elixir:elixir ${APP_DIR}

USER elixir
ENV MIX_ENV=prod

RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get --only prod && \
    mix deps.compile && \
    mix compile

EXPOSE 4000:4000

ENTRYPOINT ["./dockerfiles/phoenix/entrypoint.sh"]

CMD ["mix", "phx.server"]
