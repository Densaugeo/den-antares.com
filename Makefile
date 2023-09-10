install-dev:
	cargo install cobalt-bin

build:
	# Wipe everything in build, but not build itself (which would confuse
	# any webservers running from that folder)
	rm -rf cobalt-build/*
	cobalt build

watch:
	while true; do make build; inotifywait --recursive --event modify cobalt; done
