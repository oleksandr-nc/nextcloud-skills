# SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

app_name := $(shell sed -n 's:.*<id>\(.*\)</id>.*:\1:p' appinfo/info.xml | head -n 1)
version := $(shell sed -n 's:.*<version>\(.*\)</version>.*:\1:p' appinfo/info.xml)
build_dir := build
artifact := $(build_dir)/artifacts/$(app_name)-$(version).tar.gz

.PHONY: all build check-manifest appstore clean

all: build

# Production frontend build. Skipping this ships the plain-JavaScript page instead.
build:
	npm ci
	npm run build

# Validate appinfo/info.xml against the app store schema (needs xmllint: libxml2-utils on
# Debian/Ubuntu, preinstalled on macOS). Also catches TODO placeholders left by rename.sh.
check-manifest:
	mkdir -p $(build_dir)
	curl -sSfo $(build_dir)/info.xsd https://apps.nextcloud.com/schema/apps/info.xsd
	xmllint --noout --schema $(build_dir)/info.xsd appinfo/info.xml

# Release tarball: the app directory minus everything in .nextcloudignore, with the
# top-level directory named after the app id (what the app store and occ expect).
appstore: check-manifest build
	rm -rf $(build_dir)/$(app_name)
	mkdir -p $(build_dir)/artifacts $(build_dir)/$(app_name)
	rsync -a --exclude-from=.nextcloudignore ./ $(build_dir)/$(app_name)/
	tar -czf $(artifact) -C $(build_dir) $(app_name)
	@echo "$(artifact)"
	@tar -tzf $(artifact) | grep -cE '\.(php|mjs|css|xml)$$' | xargs printf '%s runtime files packaged\n'

clean:
	rm -rf $(build_dir) node_modules vendor
