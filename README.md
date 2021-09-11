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
    ```haproxy
    global
        # *snip*
        lua-prepend-path /usr/share/haproxy/?/http.lua # If haproxy-lua-http is saved as /usr/share/haproxy/haproxy-lua-http/http.lua
        lua-load /usr/share/haproxy/auth-request.lua
    ```

2. Define a backend that is used for the subrequests:
    ```haproxy
    backend auth_request
        mode http
        server auth_request 127.0.0.1:8080 check
    ```

3. Execute the subrequest in your frontend (as early as possible):
    ```haproxy
    frontend http
        mode http
        bind :::80 v4v6

        # *snip*

        # auth-request syntax:
        #                             Backend name     Path to request
        http-request lua.auth-request auth_request     /is-allowed

        # auth-intercept syntax:                                           (Headers to copy)
        #                               Backend name  Path         Method  Request  Success  Failure
        http-request lua.auth-intercept auth_request  /is-allowed  HEAD    *        -        -
    ```

4. Act on the results:
    ```haproxy
    frontend http
        # *snip*

        http-request deny if ! { var(txn.auth_response_successful) -m bool }
    ```

### Parameters

The scripts receive a list of parameters used to build the authentication
request:

* **Backend name**: is the name of an HAProxy backend. See the
[Inner Workings](#inner-workings) section.
* **Path to request**: the request URL sent to the auth-request backend.

The following parameters are only available in the `auth-intercept` script:

* **Method**: the HTTP method that should be used. Use an asterisk `*` to ask
`auth-intercept` to copy the same method used by the client. `auth-request`
uses the `HEAD` method.
* **Headers to copy on Request**: a comma-separated list of a simplified glob
pattern that should match the HTTP header names to copy from the client to the
auth-intercept backend. Use a dash `-` to not copy any header.
* **Headers to copy on Success**: a comma-separated list of a simplified glob
pattern that should match the HTTP header names to copy from the auth-intercept
backend to the protected backend server, if the auth-intercept backend respond
with 2xx response code and the request succeed. All headers received from the
auth-intercept will override headers with the same name provided by the client.
Use `*` to copy all headers, or use a dash `-` to not copy any header. HAProxy
variables are always created, see the [Available Variables](#available-variables)
section.
* **Headers to copy on Failure**: a comma-separated list of a simplified glob
pattern that should match the HTTP header names to copy from the auth-intercept
backend to the client, if the request failed. `auth-intercept` will use the
same HTTP method and body sent by the auth-intercept backend to respond to the
client, closing the transaction. The protected backend server will not be used.
Use `*` to copy all headers. Use a dash `-` to not close the transaction and
leave to the HAProxy configuration the task to deny the request based on the
`txn.auth_response_successful` variable. HAProxy variables are always created,
see the [Available Variables](#available-variables) section.

Simplified glob pattern: use an asterisk `*` to match any sequence of
characters and `?` to match a single char. `*` will match any header name.
`x-*` will match all header names started with `x-`. `x-????` will match
`x-user` but will not match neither `x-token` nor `x-id`.

HAProxy 2.1 or older: the On Failure param (the last one) will close the
transaction and respond to the client if the value is not a dash `-`, however
this feature is only supported on HAProxy 2.2 or newer. The only supported
option on 2.1 and older is a dash `-`.

### Available Variables

auth-request uses HAProxy variables to communicate the results back to you. The
[`var()` sample fetch] can be used to retrieve the variable contents.

The following list of variables may be set.

<dl>
<dt><code>txn.auth_response_successful</code></dt>
<dd>
Set to <code>true</code> if the subrequest returns an HTTP status code in the
<code>2xx</code> range. <code>false</code> otherwise.
</dd>

<dt><code>txn.auth_response_code</code></dt>
<dd>
The HTTP status code of the subrequest. If the subrequest did not return a
valid HTTP response the value will be <code>500</code>.
</dd>

<dt><code>txn.auth_response_location</code></dt>
<dd>
The <code>location</code> response header of the subrequest.

This variable is only set if the HTTP status code of the subrequest indicates a
redirect (i.e. <code>301</code>, <code>302</code>, <code>303</code>,
<code>307</code>, or <code>308</code>).
</dd>

<dt><code>req.auth_response_header.*</code>
<dd>
These variables store the subrequest’s response headers. The values of
duplicate response headers will be merged with a comma.

HAProxy variables may only contain alphanumeric characters, the dot
(<code>.</code>), and an underscore <code>_</code>. Any non-alphanumeric
characters will be replaced with an underscore to be representable. If the
response contains duplicate response headers <em>after</em> normalizing the
header name the result for these headers will be undefined.

Normalization examples:
<dl>
<dt><code>X-Authenticated-User</code></dt>
<dd><code>req.auth_response_header.x_authenticated_user</code></dd>
<dt><code>Success</code></dt>
<dd><code>req.auth_response_header.success</code></dd>
</dl>

Please note: The scope of the response header variables is <code>req</code>
compared to <code>txn</code> for the other variables. The contents will no
longer be available during response processing to save memory. Copy the values
of interest into a <code>txn.</code> variable if you need access them during
response processing.
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
the exception of the `content-length` header which will be stripped, because
the request body will not be forwarded.

## Known limitations

- The Lua script only supports basic health checking, without redispatching or
  load balancing of any kind.
- The backend must not be using TLS.

[ngx_http_auth_request_module]: http://nginx.org/en/docs/http/ngx_http_auth_request_module.html
[haproxy-lua-http]: https://github.com/haproxytech/haproxy-lua-http
[`lua-prepend-path`]: http://cbonte.github.io/haproxy-dconv/2.1/configuration.html#lua-prepend-path
[`var()` sample fetch]: http://cbonte.github.io/haproxy-dconv/2.2/configuration.html#7.3.2-var
