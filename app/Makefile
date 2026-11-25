.PHONY: install api-build api-dev api-prod db-up db-down db-migrate db-seed mobile-bootstrap ci

install:
	cd services/api && npm install

api-build:
	cd services/api && npm run build

api-dev:
	cd services/api && npm run start:dev

api-prod:
	cd services/api && npm run start:prod

db-up:
	docker compose up -d

pg-up:
	cd ../tools/pg && ./start.sh

pg-down:
	cd ../tools/pg && ./stop.sh

pg-migrate:
	cd ../tools/pg && node migrate.mjs

db-down:
	docker compose down

db-migrate:
	for f in db/migrations/0001_core.sql db/migrations/0002_zones_postgis.sql; do echo "applying $$f"; psql "$$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$$f"; done

db-seed:
	for f in db/seeds/*.sql; do echo "seeding $$f"; psql "$$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$$f"; done

dispatch:
	cd apps/dispatch && node serve.mjs

mobile-bootstrap:
	./scripts/bootstrap-mobile.sh

ci: api-build
