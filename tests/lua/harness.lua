-- tests/lua/harness.lua — tiny test framework + X-Ray-like stub environment.
-- Lua 5.1 / LuaJIT compatible (also tolerates 5.2+ through load(..., env)).
--
-- X-Ray (Anomaly) module semantics emulated here:
--   * every *.script is a chunk whose environment is its own module table;
--     global lookups fall back to the game's global table (metatable __index);
--   * the module table is reachable as a global named after the file;
--   * referencing a not-yet-loaded module name loads it lazily (H.lazy).
-- Each test case builds a fresh "game global" table G (H.env), so fixes are
-- reloaded per case and their file locals (logged flags, timers) start clean.

local H = {}
H.root = "."           -- set by run.lua: repository root

-------------------------------------------------------------------------------
-- framework
-------------------------------------------------------------------------------
local cases = {}

function H.case(name, fn) cases[#cases + 1] = { name = name, fn = fn } end
-- Spec requirement that the code does not meet: asserts the spec, does not fail the run.
function H.xfail(name, reason, fn) cases[#cases + 1] = { name = name, fn = fn, xfail = reason } end
function H.skip(name, reason) cases[#cases + 1] = { name = name, skip = reason } end

local function short_tb(err)
	local msg = tostring(err)
	return msg
end

function H.run_all(filter)
	local t0 = os.clock()
	local r = { pass = 0, fail = 0, xfail = 0, xpass = 0, skip = 0, failed = {}, xfailed = {}, xpassed = {} }
	for _, c in ipairs(cases) do
		if not filter or filter == "" or string.find(c.name, filter, 1, true) then
			if c.skip then
				r.skip = r.skip + 1
				print("SKIP  " .. c.name .. ": " .. c.skip)
			else
				local ok, err = xpcall(c.fn, short_tb)
				if c.xfail then
					if ok then
						r.xpass = r.xpass + 1
						r.xpassed[#r.xpassed + 1] = c.name
						print("XPASS " .. c.name .. " (expected-fail now passes; update COVERAGE.md / the test)")
					else
						r.xfail = r.xfail + 1
						r.xfailed[#r.xfailed + 1] = c.name
						print("XFAIL " .. c.name .. ": " .. err .. "  [known: " .. c.xfail .. "]")
					end
				elseif ok then
					r.pass = r.pass + 1
					print("PASS  " .. c.name)
				else
					r.fail = r.fail + 1
					r.failed[#r.failed + 1] = c.name
					print("FAIL  " .. c.name .. ": " .. err)
				end
			end
		end
	end
	print(string.rep("-", 72))
	print(string.format("lua tests: %d passed, %d failed, %d expected-fail, %d xpass, %d skipped (%.2fs)",
		r.pass, r.fail, r.xfail, r.xpass, r.skip, os.clock() - t0))
	for _, n in ipairs(r.failed) do print("  FAILED: " .. n) end
	for _, n in ipairs(r.xfailed) do print("  EXPECTED-FAIL: " .. n) end
	io.stdout:flush()
	return (r.fail == 0 and (r.pass + r.xfail + r.xpass) > 0) and 0 or 1
end

-------------------------------------------------------------------------------
-- assertions (error level 2 -> file:line of the test)
-------------------------------------------------------------------------------
local function fmt(v)
	if type(v) == "string" then return string.format("%q", v) end
	return tostring(v)
end

local function dump(v, depth)
	depth = depth or 0
	if type(v) ~= "table" then return fmt(v) end
	if depth > 4 then return "{...}" end
	local keys = {}
	for k in pairs(v) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b)
		if type(a) == type(b) and (type(a) == "number" or type(a) == "string") then return a < b end
		return type(a) < type(b)
	end)
	local parts = {}
	for _, k in ipairs(keys) do parts[#parts + 1] = "[" .. fmt(k) .. "]=" .. dump(v[k], depth + 1) end
	return "{" .. table.concat(parts, ", ") .. "}"
end
H.dump = dump

local function deep_eq(a, b)
	if a == b then return true end
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	for k, v in pairs(a) do if not deep_eq(v, b[k]) then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end
H.deep_eq = deep_eq

function H.eq(exp, act, msg)
	if exp ~= act then
		error((msg or "values differ") .. ": expected " .. fmt(exp) .. ", got " .. fmt(act), 2)
	end
end

function H.same(exp, act, msg)
	if not deep_eq(exp, act) then
		error((msg or "tables differ") .. ": expected " .. dump(exp) .. ", got " .. dump(act), 2)
	end
end

function H.truthy(v, msg)
	if not v then error(msg or "expected truthy value", 2) end
end

function H.falsy(v, msg)
	if v then error((msg or "expected falsy value") .. ", got " .. fmt(v), 2) end
end

function H.between(lo, hi, v, msg)
	if type(v) ~= "number" or v < lo or v > hi then
		error((msg or "out of range") .. ": expected [" .. lo .. ", " .. hi .. "], got " .. fmt(v), 2)
	end
end

-- log helpers -----------------------------------------------------------------
function H.log_count(G, needle)
	local n = 0
	for _, line in ipairs(G.__log) do
		if string.find(line, needle, 1, true) then n = n + 1 end
	end
	return n
end

function H.log_has(G, needle, msg)
	if H.log_count(G, needle) == 0 then
		error((msg or "log line missing") .. ": " .. fmt(needle) .. "\n    log: " .. dump(G.__log), 2)
	end
end

function H.log_lacks(G, needle, msg)
	if H.log_count(G, needle) > 0 then
		error((msg or "unexpected log line") .. ": " .. fmt(needle) .. "\n    log: " .. dump(G.__log), 2)
	end
end

-------------------------------------------------------------------------------
-- module loading
-------------------------------------------------------------------------------
local function compile(src, chunkname, env)
	src = string.gsub(src, "^\239\187\191", "")   -- UTF-8 BOM (X-Ray tolerates it)
	local f, err
	if setfenv then
		f, err = loadstring(src, "@" .. chunkname)
		if f then setfenv(f, env) end
	else
		f, err = load(src, "@" .. chunkname, "t", env)
	end
	if not f then error("compile error in " .. chunkname .. ": " .. tostring(err), 0) end
	return f
end

local function read_file(path)
	local fh, err = io.open(path, "rb")
	if not fh then error("cannot open " .. path .. ": " .. tostring(err), 0) end
	local s = fh:read("*a")
	fh:close()
	return s
end
H.read_file = read_file

-- Load `src` as X-Ray script module `name` into game globals G; returns the module table.
function H.load_module(G, name, src, chunkname)
	local env = setmetatable({}, { __index = G })
	rawset(G, name, env)
	compile(src, chunkname or (name .. ".script"), env)()
	return env
end

-- Register a module that is loaded on first reference (like the X-Ray script loader).
function H.lazy(G, name, src)
	G.__lazy[name] = src
end

-- Load a REAL fix script from mods/<mod>/gamedata/scripts/<file>.script.
function H.load_fix(G, mod, file)
	local path = H.root .. "/mods/" .. mod .. "/gamedata/scripts/" .. file .. ".script"
	return H.load_module(G, file, read_file(path), "mods/" .. mod .. "/gamedata/scripts/" .. file .. ".script")
end

-------------------------------------------------------------------------------
-- stubs
-------------------------------------------------------------------------------

-- marshal (Anomaly ships lua-marshal; this is a pure-Lua stand-in with the same
-- encode/decode contract: round-trips nil/boolean/number/string/table, errors on
-- anything else and on malformed input).
local function m_encode(v, out, depth)
	local t = type(v)
	if depth > 32 then error("marshal: table too deep", 0) end
	if t == "nil" then out[#out + 1] = "N"
	elseif t == "boolean" then out[#out + 1] = v and "T" or "F"
	elseif t == "number" then out[#out + 1] = "n" .. string.format("%.17g", v) .. ";"
	elseif t == "string" then out[#out + 1] = "s" .. #v .. ":" .. v
	elseif t == "table" then
		out[#out + 1] = "{"
		for k, val in pairs(v) do
			m_encode(k, out, depth + 1)
			m_encode(val, out, depth + 1)
		end
		out[#out + 1] = "}"
	else
		error("marshal: cannot encode a " .. t, 0)
	end
end

local function m_decode(s, pos)
	local c = string.sub(s, pos, pos)
	if c == "N" then return nil, pos + 1
	elseif c == "T" then return true, pos + 1
	elseif c == "F" then return false, pos + 1
	elseif c == "n" then
		local e = string.find(s, ";", pos, true)
		local n = e and tonumber(string.sub(s, pos + 1, e - 1))
		if not n then error("marshal: bad number at " .. pos, 0) end
		return n, e + 1
	elseif c == "s" then
		local e = string.find(s, ":", pos, true)
		local len = e and tonumber(string.sub(s, pos + 1, e - 1))
		if not len or e + len > #s then error("marshal: bad string at " .. pos, 0) end
		return string.sub(s, e + 1, e + len), e + len + 1
	elseif c == "{" then
		local t = {}
		pos = pos + 1
		while string.sub(s, pos, pos) ~= "}" do
			if pos > #s then error("marshal: unterminated table", 0) end
			local k, v
			k, pos = m_decode(s, pos)
			v, pos = m_decode(s, pos)
			if k == nil then error("marshal: nil key", 0) end
			t[k] = v
		end
		return t, pos + 1
	end
	error("marshal: bad tag " .. fmt(c) .. " at " .. pos, 0)
end

function H.marshal()
	return {
		encode = function(v)
			local out = {}
			m_encode(v, out, 0)
			return table.concat(out)
		end,
		decode = function(s)
			if type(s) ~= "string" then error("marshal: string expected", 0) end
			local v, pos = m_decode(s, 1)
			if pos ~= #s + 1 then error("marshal: trailing data", 0) end
			return v
		end,
	}
end

-- utils_data subset. string2hex/hex2string: upper-case byte hex; hex2string errors
-- on non-hex input (string.char(nil)), like a gsub-based implementation would.
function H.utils_data(G)
	G.__pstor = G.__pstor or {}
	G.__saved = G.__saved or {}
	return {
		save_var = function(obj, key, val)
			G.__saved[#G.__saved + 1] = { key = key, val = val }
			G.__pstor[key] = val
		end,
		load_var = function(obj, key, default)
			local v = G.__pstor[key]
			if v == nil then return default end
			return v
		end,
		string2hex = function(s)
			return (string.gsub(s, ".", function(c) return string.format("%02X", string.byte(c)) end))
		end,
		hex2string = function(h)
			if #h % 2 ~= 0 then error("hex2string: odd length", 0) end
			return (string.gsub(h, "..", function(cc) return string.char(tonumber(cc, 16)) end))
		end,
	}
end

-- Saved value lookup helper for utils_data.save_var stubs.
function H.saved(G, key)
	for i = #G.__saved, 1, -1 do
		if G.__saved[i].key == key then return G.__saved[i].val, true end
	end
	return nil, false
end

-- ini reader with r_string_ex / r_float_ex / section_exist over a Lua table.
function H.ini(data)
	return {
		section_exist = function(self, sec) return data[sec] ~= nil end,
		r_string_ex = function(self, sec, key)
			local s = data[sec]
			local v = s and s[key]
			return v ~= nil and tostring(v) or nil
		end,
		r_float_ex = function(self, sec, key)
			local s = data[sec]
			return s and tonumber(s[key]) or nil
		end,
		__data = data,
	}
end

-- Game objects (items, NPCs, actor). Item fields: id, section, name, condition,
-- weapon_type (255 = not a weapon), uses. Owners: inventory = {objs}, belt = {objs}.
function H.obj(o)
	o.weapon_type = o.weapon_type or 255
	o.condition_v = o.condition_v or 1
	function o:id() return self.id_v end
	function o:section() return self.section_v end
	function o:name() return self.name_v or (tostring(self.section_v) .. tostring(self.id_v)) end
	function o:condition() return self.condition_v end
	function o:get_weapon_type() return self.weapon_type end
	function o:get_remaining_uses() return self.uses or 1 end
	function o:character_name() return self.name_v end
	-- iterate_inventory(fn, arg): fn(arg, item); a true return stops (engine semantics)
	function o:iterate_inventory(fn, arg)
		for _, it in ipairs(self.inventory or {}) do
			if fn(arg, it) == true then return end
		end
	end
	function o:iterate_belt(fn, arg)
		for _, it in ipairs(self.belt or {}) do
			if fn(arg, it) == true then return end
		end
	end
	return o
end

-- Fresh game global table.
-- Callback registry mirrors axr_main: intercepts[name][func_value] = true,
-- registration for an unknown name is ignored (AddScriptCallback creates names).
local KNOWN_CALLBACKS = {
	"on_game_start", "actor_on_first_update", "actor_on_update", "load_state", "save_state",
	"npc_on_death_callback", "monster_on_death_callback", "npc_on_hit_callback", "monster_on_hit_callback",
	"npc_on_before_hit", "monster_on_before_hit", "actor_item_to_belt", "actor_item_to_ruck", "actor_item_to_slot",
	"on_option_change", "server_entity_on_unregister",
}

function H.env()
	local G = {}
	local lazy = {}
	G.__lazy = lazy
	G.__log = {}
	G.__now = 0
	G._G = G
	setmetatable(G, {
		__index = function(t, k)
			local src = lazy[k]
			if src then
				lazy[k] = nil
				return H.load_module(G, k, src, k .. ".script")
			end
			return _G[k]
		end,
	})

	G.printf = function(f, ...)
		G.__log[#G.__log + 1] = string.format(f, ...)
	end
	G.time_global = function() return G.__now end

	local intercepts = {}
	for _, n in ipairs(KNOWN_CALLBACKS) do intercepts[n] = {} end
	G.__callbacks = intercepts
	G.AddScriptCallback = function(name) intercepts[name] = intercepts[name] or {} end
	G.RegisterScriptCallback = function(name, func)
		if not intercepts[name] then
			G.__log[#G.__log + 1] = "axr_main: callback_set: " .. tostring(name) .. " not registered"
			return
		end
		intercepts[name][func] = true
	end
	G.UnregisterScriptCallback = function(name, func)
		if intercepts[name] then intercepts[name][func] = nil end
	end
	G.SendScriptCallback = function(name, ...)
		for func in pairs(intercepts[name] or {}) do func(...) end
	end

	-- _g.script: deep copy (copy_table recurses into sub-tables)
	local function copy_table(dest, src)
		for k, v in pairs(src) do
			if type(v) == "table" then
				dest[k] = {}
				copy_table(dest[k], v)
			else
				dest[k] = v
			end
		end
	end
	G.copy_table = copy_table
	G.dup_table = function(src)
		local t = {}
		copy_table(t, src)
		return t
	end
	-- _g.script spairs (GAMMA): pairs(t) errors on nil
	G.spairs = function(t, order)
		local keys = {}
		for k in pairs(t) do keys[#keys + 1] = k end
		if order then
			table.sort(keys, function(a, b) return order(t, a, b) end)
		else
			table.sort(keys)
		end
		local i = 0
		return function()
			i = i + 1
			if keys[i] then return keys[i], t[keys[i]] end
		end
	end
	return G
end

-- Registered callback functions for `name` (list).
function H.callbacks(G, name)
	local list = {}
	for f in pairs(G.__callbacks[name] or {}) do list[#list + 1] = f end
	return list
end

-- Deterministic math.random for G: records (lo, hi) of each call, returns lo..hi midpoint floor.
function H.record_random(G)
	local rec = {}
	G.math = setmetatable({
		random = function(lo, hi)
			rec[#rec + 1] = { lo = lo, hi = hi }
			return math.floor((lo + hi) / 2)
		end,
	}, { __index = math })
	return rec
end

-- Expected roll bounds for value v (xrr_quest_reward / fix roll()).
function H.roll_bounds(v)
	local d = math.floor(v * 0.1)
	return math.floor(v - d), math.floor(v + d)
end

return H
