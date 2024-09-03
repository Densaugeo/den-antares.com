install-dev:
	cargo install cobalt-bin
	npm install

build:
	# Wipe everything in build, but not build itself (which would confuse
	# any webservers running from that folder)
	rm -rf cobalt-build/*
	cobalt build
	ln -s ../../Castle/static cobalt-build/castle
	ln -s ../node_modules cobalt-build/node_modules
	npm update

watch:
	while true; do \
		make build; \
		inotifywait --recursive --event modify --exclude .kate-swp cobalt; \
	done

clean:
	cobalt clean
