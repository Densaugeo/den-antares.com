install-dev:
	cargo install cobalt-bin

build:
	cobalt build

watch:
	while true; do make build; inotifywait --event modify cobalt; done
