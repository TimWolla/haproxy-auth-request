default:

install: auth-request.lua haproxy-lua-http/http.lua
	install -d "$(DESTDIR)/usr/share/haproxy"
	install -m644 haproxy-lua-http/http.lua "$(DESTDIR)/usr/share/haproxy"
	install -m644 auth-request.lua "$(DESTDIR)/usr/share/haproxy"

.PHONY: install
