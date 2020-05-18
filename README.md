# auth-request

auth-request allows you to add access control to your HTTP services based
on a subrequest to a configured haproxy backend. The workings of this Lua
script are loosely based on the [ngx_http_auth_request_module][1] module
for nginx.

## Requirements

### Required

- haproxy 1.8.4+
- `USE_LUA=1` set at compile time.
- LuaSocket with commit [0b03eec16b](https://github.com/diegonehab/luasocket/commit/0b03eec16be0b3a5efe71bcb8887719d1ea87d60) (that is: newer than 2014-11-10) in your Lua library path (`LUA_PATH`).
  - `lua-socket` from Debian Stretch works.
  - `lua-socket` from Ubuntu Xenial works.
  - `lua-socket` from Ubuntu Bionic works.
  - `lua5.3-socket` from Alpine 3.8 works.
  - `luasocket` from luarocks *does not* work.
  - `lua-socket` v3.0.0.17.rc1 from EPEL *does not* work.
  - `lua-socket` from Fedora 28 *does not* work.

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
3. Define and Execute the subrequest in your frontend (as early as possible):
```
frontend http
	mode http
	bind :::80 v4v6
	# *snip*

	# Define a named configuration
	# 					          		Config	Backend			Path to request
	http-request lua.auth-request 		ABE		auth_request	/is-allowed

	# Store extra response headers from the backend if needed
	#									Config	Store in Var	Returned Header
	http-request lua.auth-set-header	ABE		txn.my_var		x-auth-specific
	http-request lua.auth-set-header	ABE		txn.other_var	x-auth-extra

	# Execute the subrequest
	http-request lua.auth-execute-subrequest ABE
```
4. Act on the subrequest results using the transaction variables set by the
script. The `txn.auth_response_successful`, `txn.auth_response_code`, and
`txn.auth_response_location` variables are implicitly set, in additon to any
varibles set by the header mappings:
```
frontend http
	# *snip*
	
	http-request deny if ! { var(txn.auth_response_successful) -m bool }
```

## Unnamed Auth Backend
For brevity and backwards compatibility, it is possible to execute a subrequest
without specifying a named auth backend and defining variables. This only
sets the `txn.auth_response_successful`, `txn.auth_response_code`, and
`txn.auth_response_location` variables.
```
frontend http
	mode http
	bind :::80 v4v6
	# *snip*

	#                             Backend name     Path to request
	http-request lua.auth-request auth_request     /is-allowed
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

If any `auth-set-header` directives are defined for the configuration, headers
returned by the auth backend will be stored in their corresponding transaction
variables. If the header is not present in the response, its corresponding
variable is left unset. Note that header matching is case-insensitive, so
`X-Auth-EXTRA` will match `x-auth-extra`.

## Known limitations

- The Lua script only supports basic health checking, without redispatching
  or load balancing of any kind.
- The backend must not be using TLS.

[1]: http://nginx.org/en/docs/http/ngx_http_auth_request_module.html
