# auth-request ![Test](https://github.com/TimWolla/haproxy-auth-request/workflows/Test/badge.svg)

auth-request allows you to add access control to your HTTP services based on a
subrequest to a configured HAProxy backend. The workings of this Lua script are
loosely based on the [ngx_http_auth_request_module] module for nginx.

## Requirements

- HAProxy 1.8.4+ (2.2.0+ recommended)
  - Only the latest version of each HAProxy branch is supported.
- `USE_LUA=1` must be set at compile time.
- [haproxy-lua-http] must be available within the Lua path.
  - A `json` library within the Lua path (dependency of haproxy-lua-http).
  - With HAProxy 2.1.3+ you can use the [`lua-prepend-path`] configuration
    option to specify the search path.

## Usage

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

### Available Variables

auth-request uses HAProxy variables to communicate the results back to you. The
[`var()` sample fetch] can be used to retrieve the variable contents.

The following list of variables may be set.

<dl>
	<dt><code>txn.auth_response_successful</code></dt>
	<dd>
		Set to <code>true</code> if the subrequest returns an HTTP
		status code in the <code>2xx</code> range. <code>false</code>
		otherwise.
	</dd>
	<dt><code>txn.auth_response_code</code></dt>
	<dd>
		The HTTP status code of the subrequest. If the subrequest did
		not return a valid HTTP response the value will be
		<code>500</code>.
	</dd>
	<dt><code>txn.auth_response_location</code></dt>
	<dd>
		The <code>location</code> response header of the subrequest.
		This variable is only set if the HTTP status code of the
		subrequest indicates a redirect (i.e. <code>301</code>,
		<code>302</code>, <code>303</code>, <code>307</code>, or
		<code>308</code>).
	</dd>
</dl>

## Inner Workings

The Lua script will make a HTTP request to the *first* server in the given
backend that is either marked as `UP` or that does not have checks enabled.
This allows for basic health checking of the auth-request backend. If you need
more complex processing of the request forward the auth-request to a separate
HAProxy *frontend* that performs the required modifications to the request and
response.

The requested URL is the one given in the second parameter.

Any request headers will be forwarded as-is to the auth-request backend, with
the exception of the `content-length` header which will be stripped.

## Known limitations

- The Lua script only supports basic health checking, without redispatching or
  load balancing of any kind.
- The response headers of the subrequest are not exposed outside the script.
- The backend must not be using TLS.

[ngx_http_auth_request_module]: http://nginx.org/en/docs/http/ngx_http_auth_request_module.html
[haproxy-lua-http]: https://github.com/haproxytech/haproxy-lua-http
[`lua-prepend-path`]: http://cbonte.github.io/haproxy-dconv/2.1/configuration.html#lua-prepend-path
[`var()` sample fetch]: http://cbonte.github.io/haproxy-dconv/2.2/configuration.html#7.3.2-var
