default:

install: auth-request.lua
	install -d "$(DESTDIR)/usr/share/haproxy"
	install -m644 auth-request.lua "$(DESTDIR)/usr/share/haproxy"

.PHONY: install
