-- FX-PARTS: zz_xrrfix_parts_tooltip.script (specs/fixes/fx-parts.md)
local H = ...

local MOD, FILE = "zz xrRazom Fix - Weapon Parts Tooltip", "zz_xrrfix_parts_tooltip"

-- zzzz_arti_jamming_repairs (Momopate): iterates get_parts_con(...) results with
-- spairs(parts, sort_parts) and no nil check, e.g. in its ui_item.build_desc_header.
local AJR_SRC = [==[
function sort_parts(t, a, b) return a < b end
function list_parts(parts)
	local out = {}
	for k, v in spairs(parts, sort_parts) do out[#out + 1] = k end
	return out
end
]==]

-- Some other mod using the global spairs (must keep crashing on nil: the fix is module-local).
local OTHER_SRC = [==[
function list_parts(parts)
	local out = {}
	for k, v in spairs(parts) do out[#out + 1] = k end
	return out
end
]==]

local function setup()
	local G = H.env()
	local orig_spairs = G.spairs
	local m = H.load_module(G, "zzzz_arti_jamming_repairs", AJR_SRC)
	local other = H.load_module(G, "other_mod", OTHER_SRC)
	local fix = H.load_fix(G, MOD, FILE)
	return G, fix, m, other, orig_spairs
end

H.case("FX-PARTS-001 module spairs(nil) is an empty loop, logged once", function()
	local G, fix, m = setup()
	fix.on_game_start()
	H.log_has(G, "[XRRFIX] parts tooltip: nil-safe spairs installed")
	local n = 0
	local ok, err = pcall(function()
		for _ in m.spairs(nil, m.sort_parts) do n = n + 1 end
		for _ in m.spairs(nil, m.sort_parts) do n = n + 1 end
		H.same({}, m.list_parts(nil), "module code iterating nil parts")
	end)
	H.truthy(ok, "no error: " .. tostring(err))
	H.eq(0, n, "iterations")
	H.eq(1, H.log_count(G, "parts tooltip: nil parts table skipped (logged once)"), "log lines")
end)

H.case("FX-PARTS-002 tables iterate exactly like the global spairs", function()
	local G, fix, m = setup()
	fix.on_game_start()
	local t = { b = 2, a = 1, c = 3 }
	local order = function(tt, x, y) return tt[x] > tt[y] end
	local function collect(iter)
		local out = {}
		for k, v in iter do out[#out + 1] = k .. "=" .. v end
		return out
	end
	H.same(collect(G.spairs(t, order)), collect(m.spairs(t, order)), "with order")
	H.same(collect(G.spairs(t)), collect(m.spairs(t)), "without order")
	H.same({ "c=3", "b=2", "a=1" }, collect(m.spairs(t, order)), "sequence")
end)

H.case("FX-PARTS-003 global spairs untouched, installed once", function()
	local G, fix, m, other, orig_spairs = setup()
	fix.on_game_start()
	local first = rawget(m, "spairs")
	fix.on_game_start()
	H.truthy(rawequal(orig_spairs, G.spairs), "_G.spairs unchanged")
	H.truthy(first and rawequal(first, rawget(m, "spairs")), "module spairs not replaced again")
	H.eq(true, rawget(m, "__xrrfix_spairs"), "flag set")
	H.eq(1, H.log_count(G, "nil-safe spairs installed"), "install logged once")
	local ok = pcall(other.list_parts, nil)
	H.falsy(ok, "other modules still use the original global spairs (errors on nil)")
end)
