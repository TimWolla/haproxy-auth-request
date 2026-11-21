-- SPDX-License-Identifier: MIT

-- Standalone unit test for the hop-by-hop blocklist in header_match().
--
-- The .vtc tests drive header_match() through a live HAProxy and a varnishtest
-- server, so they cannot cheaply pin down every entry of HOP_BY_HOP_HEADERS,
-- nor prove that a blocklisted header stays blocked when an operator asks for
-- it by name. This file calls header_match() directly and needs only a Lua
-- interpreter, no HAProxy:
--
--   lua test/header_match.lua
--
-- The path to auth-request.lua is derived from this script's own location, so
-- the command above also works from outside the repository root.
--
-- auth-request.lua performs side effects at load time, requiring
-- haproxy-lua-http and registering actions, so both are stubbed out first.

package.preload["haproxy-lua-http"] = function()
	return {}
end

core = {
	register_action = function() end,
	register_fetches = function() end,
	backends = {},
}

-- Load auth-request.lua relative to this script, so the working directory does
-- not matter. arg[0] is the script path as it was invoked.
local script_dir = (arg[0]:match("^(.*)/[^/]*$")) or "."
local auth_request_path = script_dir .. "/../auth-request.lua"

assert(loadfile(auth_request_path))()

local failures = 0

local function check(desc, got, want)
	if got == want then
		io.stdout:write(string.format("ok       %s\n", desc))
	else
		failures = failures + 1
		io.stderr:write(string.format("FAIL     %s: got %s, want %s\n", desc, tostring(got), tostring(want)))
	end
end

-- Every header name handed to header_match() is lowercase: HAProxy lowercases
-- the keys returned by req_get_headers() and haproxy-lua-http lowercases
-- response header names while parsing them. HOP_BY_HOP_HEADERS relies on that
-- contract, so the expected names are written in lowercase here as well.
local HOP_BY_HOP = {
	"connection",
	"proxy-connection",
	"keep-alive",
	"upgrade",
	"te",
	"trailer",
	"transfer-encoding",
	"content-length",
	"host",
}

-- The `*` glob is what the auth-request action hardcodes and the value
-- auth-intercept users reach for most often, so it is the pattern under which
-- the blocklist matters most.
local MATCH_ALL = globToLuaPattern("*")

-- 1. No hop-by-hop header may be copied, whatever the configured pattern says.
for _, header in ipairs(HOP_BY_HOP) do
	check("blocked under '*': " .. header, header_match(header, MATCH_ALL), false)
end

-- 2. The blocklist must also win when an operator names the header explicitly.
--    That is a correctness requirement and not a filtering convenience: copying
--    "connection: upgrade" onto the auth probe produces a request the frontend
--    cannot service, because the probe is a plain HEAD.
for _, header in ipairs(HOP_BY_HOP) do
	check("blocked when requested by name: " .. header, header_match(header, "^" .. header .. "$"), false)
end

-- 3. Ordinary headers must keep matching, so that widening the two hardcoded
--    content-length/host comparisons into a table did not swallow names that
--    merely resemble a blocklisted one.
check("x-user matches x-*", header_match("x-user", globToLuaPattern("x-*")), true)
check("token matches x-*,token", header_match("token", globToLuaPattern("x-*,token")), true)
check("content-type matches content-*", header_match("content-type", globToLuaPattern("content-*")), true)
check("x-te matches x-te", header_match("x-te", globToLuaPattern("x-te")), true)
check("hosted matches hosted", header_match("hosted", globToLuaPattern("hosted")), true)

-- 4. A dash still means "copy no headers at all". Both spellings matter: the
--    raw dash auth_request compares against, and the dash returned unchanged
--    by globToLuaPattern.
check("dash pattern copies nothing", header_match("x-user", "-"), false)
check("globbed dash copies nothing", header_match("x-user", globToLuaPattern("-")), false)

-- 5. The blocklist keys must stay lowercase to keep matching the names HAProxy
--    and haproxy-lua-http hand back. A future edit writing "Connection" would
--    be invisible to the end-to-end tests, so catch it here.
for _, header in ipairs(HOP_BY_HOP) do
	check("blocklist key is lowercase: " .. header, header, header:lower())
end

-- 6. Negative matching (a header that matches no pattern must be skipped) is
--    deliberately not asserted. Splitting the comma-separated list with
--    `pattern:gmatch("[^,]*")` yields empty pieces, and on some Lua releases
--    `("other"):match("")` returns "", which is truthy, so every header
--    "matches". That behaviour predates the blocklist, is visible in every
--    globToLuaPattern result, and belongs to a separate change.
local empty_piece_matches = false
for piece in ("a,b"):gmatch("[^,]*") do
	if piece == "" and ("other"):match("") then
		empty_piece_matches = true
	end
end
if empty_piece_matches then
	io.stdout:write("note     an empty piece from gmatch(\"[^,]*\") matches every header on this Lua\n")
end

if failures > 0 then
	io.stderr:write(string.format("%d check(s) failed\n", failures))
	os.exit(1)
end

io.stdout:write("all checks passed\n")
