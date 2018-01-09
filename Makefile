default:

install: auth_request.lua
	install -d "$(DESTDIR)/usr/share/haproxy"
	install -m644 auth_request.lua "$(DESTDIR)/usr/share/haproxy"

.PHONY: install
