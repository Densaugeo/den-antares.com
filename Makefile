# If no date is given, date -d defaults to the start of the current day
DATE_TS=$(shell date -d '$(DATE)' '+%s')

install-dev:
	sudo dnf install inotify-tools goaccess
	cargo install cobalt-bin
	npm install
	python -m pip install reloadserver

install-prod:
	# Written for use with my Fedora 40 VPS from Hetzner
	ssh den-antares.com "dnf install -y git gcc-c++ npm caddy"
	# Rust must be installed with the shell script. If it is installed from
	# the Fedora repo, cargo commands will not be added to $PATH, and the
	# fixes for this involve editing .bashrc scripts which I really don't
	# want to automate
	ssh den-antares.com "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
	ssh den-antares.com "cargo install cobalt-bin"
	ssh den-antares.com "mkdir /den-antares.com-scratch"
	ssh den-antares.com "cd / && git clone https://github.com/Densaugeo/den-antares.com.git"
	ssh den-antares.com "cd /den-antares.com && npm install"
	ssh den-antares.com "mv /etc/caddy/Caddyfile /etc/caddy/Caddyfile-default"
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
	ln -s /den-antares.com-scratch cobalt-build/scratch
	npm update

watch:
	while true; do \
		make build; \
		inotifywait --recursive --event modify --exclude .kate-swp cobalt; \
	done

test-manual: test.pem
	cd cobalt-build && python -m reloadserver -c ../test.pem

test.pem:
	openssl req -x509 -out test.pem -keyout test.pem -newkey rsa:3072 \
		-nodes -sha256 -subj '/CN=test' -days 10000

deploy:
	ssh den-antares.com "cd /den-antares.com && git reset --hard HEAD"
	ssh den-antares.com "cd /den-antares.com && git pull"
	ssh den-antares.com "cd /den-antares.com && make build"

# If no date is given, date -d defaults to the start of the current day
DATE_TS=$(shell date -d '$(DATE)' '+%s')

check-access-log: access.log
ifdef DATE
	cat access.log | \
	jq -c "select(.ts >= $(DATE_TS) and .ts < $(DATE_TS) + 86400)" | \
	goaccess --log-format=CADDY
else
	goaccess --log-format=CADDY access.log
endif

access.log:
	scp den-antares.com:/var/lib/caddy/access.log .

clean:
	cobalt clean
	rm test.pem access.log
