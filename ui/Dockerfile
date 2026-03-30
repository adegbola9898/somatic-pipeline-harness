FROM python:3.11-slim

WORKDIR /site
COPY . /site

EXPOSE 8080

CMD ["sh", "-c", "python -m http.server ${PORT:-8080} --bind 0.0.0.0 -d /site"]
