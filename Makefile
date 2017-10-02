.PHONY: init-local apply-schema tear-down-db push pull

#@docker stop $(docker ps -a -q)
#@docker rm $(docker ps -a -q)
#@docker rmi $(docker images -q)

SHELL := /bin/bash
DB_NAME := nfl-db
IMAGE_NAME := nfl-db
PGUSER := postgres
PGPASSWORD := postgres
mkfile_path := $(abspath $(lastword $(MAKEFILE_LIST)))
current_dir := $(dir $(mkfile_path))

build:
	@docker build -t ${IMAGE_NAME} .

run:
	@docker run -d --restart=always \
		-p 5432:5432 \
		-e POSTGRES_USER=${PGUSER} \
		-e POSTGRES_PASSWORD=${PGPASSWORD} \
		-v /opt/${DB_NAME}-data/:/var/lib/postgresql/data \
		${IMAGE_NAME}:latest

command-line:
	@docker cp ./nfldb.sql postgres:/tmp/nfldb.sql
	@docker run -it \
		postgres:9.3 /bin/bash

psql:
	@docker run -it --net="host" --rm \
		-e PGUSER=${PGUSER} \
		-e PGPASSWORD=${PGPASSWORD} \
		postgres:9.3 \
		psql -h "localhost" -d nfldb

setup:
	@wget -r http://burntsushi.net/stuff/nfldb/nfldb.sql.zip && unzip -o nfldb.sql.zip
	@docker cp ./init.sh postgres:/tmp/init.sh
	@docker cp ./nfldb.sql postgres:/docker-entrypoint-initdb.d/nfldb.sql
	@docker exec -i postgres bin/sh /tmp/init.sh
	@docker exec -i postgres psql -h localhost -U ${PGUSER} -d nfldb -a -f /docker-entrypoint-initdb.d/nfldb.sql
	@rm -r nfldb.*

create-new-db:
	@docker run \
		-d --name="postgres" \
		-p 5432:5432 \
		-e POSTGRES_USER=${PGUSER} \
		-e POSTGRES_PASSWORD=${PGPASSWORD} \
		-v /opt/${DB_NAME}-data/:/var/lib/postgresql/data \
		postgres:9.3

delete-db:
	$(MAKE) tear-down-db
	$(MAKE) delete-db-data

start-db-if-exists:
	@[[ `docker ps -f "name=postgres" -f "status=exited" --format '{{.Names}}'` == "postgres" ]] && \
	(	echo "Starting Postgres" && \
		docker start postgres) || \
	echo "Postgres does not need to be started"

create-db-if-not-exists:
	@sudo mkdir -p /opt/${DB_NAME}-data/
	@[[ `docker ps -f "name=postgres" --format '{{.Names}}'` == "postgres" ]] || \
	(	echo "Creating DB" && \
		docker run --restart="always" -d --name="postgres" \
			-p 5432:5432 \
			-e POSTGRES_USER=${PGUSER} \
			-e POSTGRES_PASSWORD=${PGPASSWORD} \
			-v /opt/${DB_NAME}-data/:/var/lib/postgresql/data \
			postgres \
	)

check-already-running:
	@[[ `docker ps -f "name=postgres" -f "status=running" --format '{{.Names}}'` == "postgres" ]] && echo "DB is running"

init-local:
	@$(MAKE) start-db-if-exists --no-print-directory
	@$(MAKE) create-db-if-not-exists --no-print-directory
	@$(MAKE) check-already-running --no-print-directory
	#@$(MAKE) apply-schema --no-print-directory

apply-schema:
	@docker pull localhost:5000/postgres-script-runner:latest
	@docker run -it --net="host" --rm -v ${current_dir}/sql:/sqlscripts \
		-e RDS_SERVER=${RDS_SERVER} \
		-e RDS_DATABASE=${RDS_DATABASE} \
		-e RDS_USER=${RDS_USER} \
		-e RDS_PASSWORD=${RDS_PASSWORD} \
		localhost:5000/postgres-script-runner:latest

tear-down-db:
	[[ `docker ps -f "name=postgres" --format '{{.Names}}'` == postgres ]] && docker rm -f postgres

delete-db-data:
	@sudo rm -rf /opt/${DB_NAME}-data/
	#@sudo mkdir /opt/${DB_NAME}-data/

copy-db-from-env:
	@$(MAKE) tear-down-db --no-print-directory
	@$(MAKE) delete-db-data --no-print-directory
	@$(MAKE) create-db-if-not-exists --no-print-directory
	@$(MAKE) wait-for-db-ready --no-print-directory
	docker run --net="host" --rm \
			-e PGPASSWORD=${RDS_PASSWORD} \
			-e RDS_DATABASE=${RDS_DATABASE} \
			-e RDS_USER=${RDS_USER} \
			-e RDS_SERVER=${RDS_SERVER} \
			postgres \
				/bin/sh -c 'pg_dump -h ${RDS_SERVER} -U ${RDS_USER} ${RDS_DATABASE} | PGPASSWORD="${LOCAL_RDS_PASSWORD}" psql -h ${LOCAL_RDS_SERVER} -U ${LOCAL_RDS_USER} ${LOCAL_RDS_DATABASE}'

copy-table-to-env:
	docker run --net="host" --rm \
			-e PGPASSWORD=${RDS_PASSWORD} \
			-e RDS_DATABASE=${RDS_DATABASE} \
			-e RDS_USER=${RDS_USER} \
			-e RDS_SERVER=${RDS_SERVER} \
			postgres \
				/bin/sh -c 'pg_dump -h ${RDS_SERVER} -U ${RDS_USER} -t ${DB_TABLE} ${RDS_DATABASE} | PGPASSWORD="${LOCAL_RDS_PASSWORD}" psql -h ${LOCAL_RDS_SERVER} -U ${LOCAL_RDS_USER} ${LOCAL_RDS_DATABASE}'

pull:
	@sudo aws s3 cp s3://awsdhubnp-vehicle-local-db/translation/${DB_NAME}-data.tar.gz ./${DB_NAME}-data.tar.gz;\
	sudo tar -zxf ${DB_NAME}-data.tar.gz -C /opt/${DB_NAME}-data/

push:
	@sudo tar -zcf ${DB_NAME}-data.tar.gz -C /opt/${DB_NAME}-data/ .;\
	sudo aws s3 cp ./${DB_NAME}-data.tar.gz s3://awsdhubnp-vehicle-local-db/translation/${DB_NAME}-data.tar.gz
