install-dev:
	cargo install cobalt-bin

build:
	# Wipe everything in build, but not build itself (which would confuse
	# any webservers running from that folder)
	rm -rf cobalt-build/*
	cobalt build
	ln -s ../../Castle/static cobalt-build/castle

watch:
	while true; do make build; inotifywait --recursive --event modify cobalt; done

clean:
	cobalt clean
