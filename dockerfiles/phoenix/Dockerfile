ARG ELIXIR_VERSION=1.14.5
ARG OTP_VERSION=24.2.1

FROM ghcr.io/h3poteto/pleroma:1.14.5-otp24-slim as builder

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

RUN mkdir release && \
    mix release --path release


FROM debian:bullseye-slim

RUN apt-get update -y && apt-get install -y --no-install-recommends \
    libstdc++6 \
    openssl \
    libncurses5 \
    locales \
    libmagic-dev \
    imagemagick \
    ffmpeg \
    libimage-exiftool-perl \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

ARG HOME=/opt/pleroma
ARG DATA=/var/lib/pleroma

RUN mkdir -p ${DATA}/uploads &&\
    mkdir -p ${DATA}/static/emoji/custom && \
    chown -R nobody ${DATA} &&\
    mkdir -p /etc/pleroma &&\
    chown -R nobody /etc/pleroma

COPY --from=builder --chown=nobody:root /var/opt/app/release ${HOME}
COPY --chown=nobody:root ./priv/static/emoji/custom ${DATA}/static/emoji/custom
COPY --chown=nobody:root ./config/prod.secret.exs /etc/pleroma/config.exs

WORKDIR ${HOME}

USER nobody

CMD ["/opt/pleroma/bin/pleroma", "start"]
