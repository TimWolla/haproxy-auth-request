# auth-request ![Test](https://github.com/TimWolla/haproxy-auth-request/workflows/Test/badge.svg)

auth-request allows you to add access control to your HTTP services based
on a subrequest to a configured HAProxy backend. The workings of this Lua
script are loosely based on the [ngx_http_auth_request_module][1] module
for nginx.

## Requirements

### Required

- HAProxy 1.8.4+ (2.2.0+ recommended)
  - Only the latest version of each HAProxy branch is supported.
- `USE_LUA=1` must be set at compile time.
- [haproxy-lua-http](https://github.com/haproxytech/haproxy-lua-http) must be available within the Lua path.
  - A `json` library within the Lua path (dependency of haproxy-lua-http).
  - With HAProxy 2.1.3+ you can use the [`lua-prepend-path`](http://cbonte.github.io/haproxy-dconv/2.1/configuration.html#lua-prepend-path) configuration option to specify the search path.

## Set-Up

1. Load this Lua script in the `global` section of your `haproxy.cfg`:
```
global
	# *snip*
	lua-prepend-path /usr/share/haproxy/?/http.lua # If haproxy-lua-http is saved as /usr/share/haproxy/haproxy-lua-http/http.lua
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
backend that is either marked as `UP` or that does not have checks enabled.
This allows for basic health checking of the auth-request backend. If you
need more complex processing of the request forward the auth-request to a
separate haproxy *frontend* that performs the required modifications to the
request and response.

The requested URL is the one given in the second parameter.

Any request headers will be forwarded as-is to the auth-request backend.

The Lua script will define the `txn.auth_response_successful` variable as
true iff the subrequest returns an HTTP status code of `2xx`. The status code
of the subrequest will be returned in `txn.auth_response_code`. If the
subrequest does not return a valid HTTP response the status code is set
to `500 Internal Server Error`.

Iff the auth backend returns a status code indicating a redirect (301, 302, 303,
307, or 308) the `txn.auth_response_location` variable will be filled with the
contents of the `location` response header.

## Known limitations

- The Lua script only supports basic health checking, without redispatching
  or load balancing of any kind.
- The response headers of the subrequest are not exposed outside the script.
- The backend must not be using TLS.

[1]: http://nginx.org/en/docs/http/ngx_http_auth_request_module.html
