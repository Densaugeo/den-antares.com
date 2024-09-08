install:
	cargo install cobalt-bin
	npm install

install-dev:
	make install
	python -m pip install reloadserver

build:
	# Wipe everything in build, but not build itself (which would confuse
	# any webservers running from that folder)
	rm -rf cobalt-build/*
	cobalt build
	ln -s ../node_modules cobalt-build/node_modules
	npm update

watch:
	while true; do \
		make build; \
		inotifywait --recursive --event modify --exclude .kate-swp cobalt; \
	done

serve: test.pem
	cd cobalt-build && python -m reloadserver -c ../test.pem

test.pem:
	openssl req -x509 -out test.pem -keyout test.pem -newkey rsa:3072 \
		-nodes -sha256 -subj '/CN=test' -days 10000

clean:
	cobalt clean
	rm test.pem
