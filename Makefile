SHELL := /bin/bash

build:
	docker compose build

up:
	docker compose up -d

down:
	docker compose down

generate-data:
	bash ./scripts/generate_data.sh

check:
	docker compose exec client bash /workspace/scripts/check_protocols.sh

quick:
	docker compose exec client bash /workspace/scripts/run_quick_test.sh

experiment:
	docker compose exec client bash /workspace/scripts/run_experiment.sh

analyze:
	docker compose exec client python3 /workspace/scripts/analyze.py

clean-results:
	rm -f results/raw/*.csv results/summary/*.csv results/plots/*.png

clean-netem:
	docker compose exec client bash /workspace/scripts/clear_netem.sh
