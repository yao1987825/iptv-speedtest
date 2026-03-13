FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    curl \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /app/scripts

ENV PYTHONUNBUFFERED=1
ENV TZ=Asia/Shanghai

COPY scripts/*.py /app/scripts/

RUN chmod +x /app/scripts/*.py || true

EXPOSE 8080

CMD ["python3", "/app/scripts/speedtest_v2.py"]
