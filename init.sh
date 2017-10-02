initdb -D /var/lib/postgres/data --locale=en_US.UTF-8 --encoding=UNICODE

systemctl restart postgresql

createuser -U postgres -E -P nfldb

createdb -U postgres -O nfldb nfldb

psql -U postgres -c 'CREATE EXTENSION fuzzystrmatch;' nfldb