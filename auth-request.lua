-- The MIT License (MIT)
--
-- Copyright (c) 2018 Tim Düsterhus
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.


-- Define, customize, and execute subrequests for purposes of authenticating
-- incoming requests. Registers functions for creating backends (auth-backend),
-- storing response headers in variables (auth-set-header), and executing the
-- subrequest (auth-execute-subrequst).
--
-- For compatibility and brevity, an extra function is provided to create and
-- execute a request (auth-request) in a single directive without having to go
-- through the individual steps of creation, customization, and execution.
--
-- Multiple configurations can also be created to handle circumstances where
-- many backends must be queried, possibly conditionally.

local http = require("socket.http")

-- Creates an empty auth backend structure. Header mappings are filled in later.
function _create_backend(name, backend_name, backend_path)
	local auth_backend = {}
	auth_backend["name"] = name
	auth_backend["backend_name"] = backend_name
	auth_backend["backend_path"] = backend_path
	auth_backend["header_mapping"] = {}

	return auth_backend
end


-- Create a new backend with an empty header mapping.
-- The Header Mapping must be filled in with the auth_set_header function.
function auth_backend(txn, name, backend_name, backend_path)
	-- Set up the local auth_backends variable if it doesn't already exist
	local auth_backends = txn:get_priv()
	if auth_backends == nil then
		auth_backends = {}
		txn:set_priv(auth_backends)
	end
	
	if type(auth_backends) ~= 'table' then
		txn:Alert("Auth Backends is not a table. Possibly competing with another script.")
		txn:set_var("txn.auth_response_code", 500)
		return
	end
	
	-- Create a new object to accumulate the backend's settings.
	local auth_backend = auth_backends[name]
	if auth_backend == nil then
		auth_backend = _create_backend(name, backend_name, backend_path)

		-- Add the new backend definition to the local transaction value
		auth_backends[name] = auth_backend
	else
		txn:Alert("Redeclaration of auth configuration '" .. name .. "'")
		txn:set_var("txn.auth_response_code", 500)
	end
end
core.register_action("auth-backend", { "http-req" }, auth_backend, 3)


-- Internal function for normalizing header names. Normalization is a simple
-- Lower-Case for now.
--
-- Note that other transformations are possible, which could be beneficial for
-- backends that return slightly inconsistent header names, or for automatically
-- generated returns.
-- 
-- Leave these commented for now, and consider switching them on conditionally.
function _normalize_header_name(name)
	-- name = name:gsub("^\\.+", "")
	-- name = name:gsub("[- \\.]", "_")
	-- name = name:gsub("[^a-zA-Z0-9_]", "")
	name = name:lower()

	return name
end


-- Add or replace a mapping from returned header to a transaction variable.
-- Variables added to a named configuration will be set if a matching header is
-- returned by the auth backend.
function auth_set_header(txn, name, output_name, header_name)
	-- Fetch and sanity-check the named auth backend.
	local auth_backends = txn:get_priv()
	if auth_backends == nil then
		txn:Alert("No auth backends are defined.")
		txn:set_var("txn.auth_response_code", 500)
		return
	end
	
	if type(auth_backends) ~= 'table' then
		txn:Alert("Auth Backends is not a table. Possibly clobbered by another script.")
		txn:set_var("txn.auth_response_code", 500)
		return
	end

	local auth_backend = auth_backends[name]
	if auth_backend == nil then
		txn:Alert("The auth configuration named '" .. name .. "' is not defined.")
		txn:set_var("txn.auth_response_code", 500)
		return
	end

	-- Add the header mapping, or replace it if it exists.
	local normalized_name = _normalize_header_name(header_name)
	auth_backend["header_mapping"][normalized_name] = output_name
end
core.register_action("auth-set-header", { "http-req" }, auth_set_header, 3)


-- Internal function for executing subrequests. Dispatches request based upon
-- the provided configuration object, setting the following transaction
-- variables:
--   - txn.auth_response_code
--   - txn.auth_response_location
--   - txn.auth_response_successful
--
-- If the configuration specifies any header-to-variable mappings, set them as
-- well.
function _execute_subrequest(txn, subrequest_config)
	local be = subrequest_config["backend_name"]
	if be == nil then
		txn:Alert("Backend name not defined for subrequest " .. subrequest_config["name"])
		txn:set_var("txn.auth_response_code", 500)
		return
	end

	local path = subrequest_config["backend_path"]

	txn:set_var("txn.auth_response_successful", false)

	-- Check whether the given backend exists.
	if core.backends[be] == nil then
		txn:Alert("Unknown auth-request backend '" .. be .. "'")
		txn:set_var("txn.auth_response_code", 500)
		return
	end

	-- Check whether the given backend has servers that
	-- are not `DOWN`.
	local addr = nil
	for name, server in pairs(core.backends[be].servers) do
		local status = server:get_stats()['status']
		if status == "no check" or status:find("UP") == 1 then
			addr = server:get_addr()
			break
		end
	end
	if addr == nil then
		txn:Warning("No servers available for auth-request backend: '" .. be .. "'")
		txn:set_var("txn.auth_response_code", 500)
		return
	end

	-- Transform table of request headers from haproxy's to
	-- socket.http's format.
	local headers = {}
	for header, values in pairs(txn.http:req_get_headers()) do
		if header ~= 'content-length' then
			for i, v in pairs(values) do
				if headers[header] == nil then
					headers[header] = v
				else
					headers[header] = headers[header] .. ", " .. v
				end
			end
		end
	end

	-- Make request to backend.
	local b, c, response_headers = http.request {
		url = "http://" .. addr .. path,
		headers = headers,
		create = core.tcp,
		-- Disable redirects, because DNS does not work here.
		redirect = false,
		-- We do not check body, so HEAD
		method = "HEAD",
	}

	-- Check whether we received a valid HTTP response.
	if b == nil then
		txn:Warning("Failure in auth-request backend '" .. be .. "': " .. c)
		txn:set_var("txn.auth_response_code", 500)
		return
	end

	txn:set_var("txn.auth_response_code", c)

	-- 2xx: Allow request.
	if 200 <= c and c < 300 then
		txn:set_var("txn.auth_response_successful", true)
	-- Don't allow other codes.
	-- Codes with Location: Passthrough location at redirect.
	elseif c == 301 or c == 302 or c == 303 or c == 307 or c == 308 then
		txn:set_var("txn.auth_response_location", response_headers["location"])
	-- 401 / 403: Do nothing, everything else: log.
	elseif c ~= 401 and c ~= 403 then
		txn:Warning("Invalid status code in auth-request backend '" .. be .. "': " .. c)
	end
	
	-- If any header mappings are specified, iterate over the returned headers
	-- and try to return them. Return early if nothing has been specified.
	local mappings = subrequest_config["header_mapping"]
	if (header_mapping == nil) or (header_mapping == {}) then
		return
	end

	for header_name, value in pairs(response_headers) do
		normalized_name = _normalize_header_name(header_name)
		local mapping = mappings[normalized_name]

		if mapping ~= nil then
			txn:set_var(mapping, value)
		end
	end
end


-- Execute a subrequest and copy any mapped headers to transaction variables.
-- Retrieves configuration object and hands off to _execute_subrequest.
function auth_execute_subrequest(txn, name)
	-- TODO Validation/sanity check
	local auth_backends = txn:get_priv()
	if auth_backends == nil then
		txn:Alert("Auth Backends are not defined.")
		txn:set_var("txn.auth_response_code", 500)
		return
	end
	
	local auth_backend = auth_backends[name]
	if auth_backend == nil then
		txn:Alert("No auth configuration named '" .. name .. "'.")
		txn:set_var("txn.auth_response_code", 500)
		return
	end

	_execute_subrequest(txn, auth_backend)
end
core.register_action("auth-execute-subrequest", { "http-req" }, auth_execute_subrequest, 1)


-- Compatibility shim for original syntax. Does not save any headers, and only
-- sets the txn.auth_response_code, txn.auth_response_location, and
-- txn.auth_response_successful variables.
-- 
-- Creates an anonymous configuration object and passes it to
-- _execute_subrequest
function auth_request(txn, backend_name, path)
	local auth_backend = _create_backend(backend_name .. path, backend_name, path)
	_execute_subrequest(txn, auth_backend)
end
core.register_action("auth-request", { "http-req" }, auth_request, 2)
