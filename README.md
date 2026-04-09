# LitmarketDb

Отдельный Docker-контейнер с MySQL для локальной разработки проекта Litmarket.

## Запуск

```bash
docker-compose up -d
```

MySQL будет доступен на порту `3307` хоста.

## Импорт дампа

Импорт выполняется через `make`. Контейнер запустится автоматически если не запущен.

**По умолчанию** берёт дамп из `/home/grey/LitmarketProject/litmarket/mysql-init.sql`:

```bash
make import
```

**Из произвольного файла:**

```bash
make import SQL_SOURCE=/path/to/dump.sql
```

или позиционным аргументом:

```bash
make import /path/to/dump.sql
```

> Импорт полностью сбрасывает БД (drop + recreate) перед загрузкой. Прогресс отображается через `pv`.

После импорта можно открыть MySQL-шелл:

```bash
make shell
```

## Подключение к основному проекту (litmarket)

В файле `/home/litmarket/.env` установить:

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
