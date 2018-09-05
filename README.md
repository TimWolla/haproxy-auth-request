# auth-request

auth-request allows you to add access control to your HTTP services based
on a subrequest to a configured haproxy backend. The workings of this Lua
script are loosely based on the [ngx_http_auth_request_module][1] module
for nginx.

## Requirements

### Required

- haproxy 1.8.0+
- `USE_LUA=1` set at compile time.
- LuaSocket with commit [0b03eec16b](https://github.com/diegonehab/luasocket/commit/0b03eec16be0b3a5efe71bcb8887719d1ea87d60) (that is: newer than 2014-11-10) in your Lua library path (`LUA_PATH`).
  - `lua-socket` from Debian Stretch works.
  - `lua-socket` from Ubuntu Xenial works.
  - `lua-socket` from Ubuntu Bionic works.
  - `lua5.3-socket` from Alpine 3.8 works.
  - `luasocket` from luarocks *does not* work.
  - `lua-socket` v3.0.0.17.rc1 from EPEL *does not* work.
  - `lua-socket` from Fedora 28 *does not* work.

### Recommended

- haproxy 1.8.4+ for IPv6 support, see [Known Limitations](#known-limitations).

## Set-Up

1. Load this Lua script in the `global` section of your `haproxy.cfg`:
```
global
	# *snip*
	lua-load /usr/share/haproxy/auth-request.lua
```
2. Define a backend that is used for the subrequests:
```
backend auth_request
	mode http
	server auth_request 127.0.0.1:8080 check
```
3. Execute the subrequest in your frontend (as early as possible):
```
frontend http
	mode http
	bind :::80 v4v6
	# *snip*

	#                             Backend name     Path to request
	http-request lua.auth-request auth_request     /is-allowed
```
4. Act on the results:
```
frontend http
	# *snip*
	
	http-request deny if ! { var(txn.auth_response_successful) -m bool }
```

## The Details

The Lua script will make a HTTP request to the *first* server in the given
backend that is *not* marked as `DOWN`. This allows for basic health checking
of the auth-request backend. If you need more complex processing of the
request forward the auth-request to a separate haproxy *frontend* that
performs the required modifications to the request and response.

The requested URL is the one given in the second parameter.

Any request headers will be forwarded as-is to the auth-request backend.

The Lua script will define the `txn.auth_response_successful` variable as
true iff the subrequest returns an HTTP status code of `2xx`. The status code
of the subrequest will be returned in `txn.auth_response_code`. If the
subrequest does not return a valid HTTP response the status code is set
to `500 Internal Server Error`.

## Known limitations

- The Lua script only supports basic health checking, without redispatching
  or load balancing of any kind.
- The response headers of the subrequest are not exposed outside the script.
- The backend must not be using TLS.
- IPv6 is only supported in haproxy 1.8.4+ (released on 2018-02-08), due
  [do a bug][2]. You can [monkeypatch by reverting commit 57950b4][3].

[1]: http://nginx.org/en/docs/http/ngx_http_auth_request_module.html
[2]: http://git.haproxy.org/?p=haproxy-1.8.git;a=commit;h=9db449a701cd9e43a04f49e2e477193fa5636323
[3]: https://github.com/TimWolla/haproxy-auth-request/commit/57950b4639542ba429e54b959604e33237c6cffe
