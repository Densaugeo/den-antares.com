install-dev:
	cargo install cobalt-bin
	npm install
	python -m pip install reloadserver

install-prod:
	# Written for use with my Fedora 40 VPS from Hetzner
	ssh den-antares.com "dnf install -y git gcc-c++ npm cargo caddy"
	ssh den-antares.com "cargo install cobalt-bin"
	ssh den-antares.com "cd / && git clone https://github.com/Densaugeo/den-antares.com.git"
	ssh den-antares.com "cd /den-antares.com && npm install"
	ssh den-antares.com "mv /etc/caddy/Caddyfile /ect/caddy/Caddyfile-default"
	ssh den-antares.com "ln -s /den-antares.com/Caddyfile /etc/caddy/Caddyfile"
	ssh den-antares.com "systemctl enable caddy"
	ssh den-antares.com "systemctl start caddy"
	make deploy

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

deploy:
	ssh den-antares.com "cd /root/den-antares.com && git pull"
	ssh den-antares.com "cd /root/den-antares.com && make build"

clean:
	cobalt clean
	rm test.pem
