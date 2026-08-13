FROM python:3.13-slim

RUN apt-get update \
    && apt-get install --no-install-recommends --yes ca-certificates curl openssl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 10001 app

WORKDIR /app
COPY --chown=app:app backend /app/backend
USER app

ENV PYTHONUNBUFFERED=1 \
    DATABASE_PATH=/data/notification-backend.sqlite3

EXPOSE 8080
CMD ["python", "-m", "backend.notification_backend", "serve", "--host", "0.0.0.0"]
