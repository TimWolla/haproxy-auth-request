# SPDX-License-Identifier: MIT

default:

install: auth-request.lua haproxy-lua-http/http.lua
	git submodule update --init
	install -d "$(DESTDIR)/usr/share/haproxy"
        install -d "$(DESTDIR)/usr/share/haproxy/haproxy-lua-http"
	install -m644 haproxy-lua-http/http.lua "$(DESTDIR)/usr/share/haproxy/haproxy-lua-http"
	install -m644 auth-request.lua "$(DESTDIR)/usr/share/haproxy"

.PHONY: install
