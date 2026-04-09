# LitmarketDb

Отдельный Docker-контейнер с MySQL для локальной разработки проекта Litmarket.

## Запуск

```bash
docker-compose up -d
```

MySQL будет доступен на порту `3307` хоста.

## Подключение к основному проекту (litmarket)

В файле `/home/grey/LitmarketProject/litmarket/.env` установить:

```env
DB_CONNECTION=mysql
DB_HOST=host.docker.internal
DB_PORT=3307
DB_DATABASE=lm_db
DB_USERNAME=mysql
DB_PASSWORD=litmarket
```

> `host.docker.internal` работает потому что в `docker-compose.yml` основного проекта у сервиса `app` прописано `extra_hosts: host.docker.internal:host-gateway`.
> Это позволяет контейнеру обращаться к портам хост-машины, на которых слушает этот контейнер с БД.
