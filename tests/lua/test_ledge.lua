-- FX-LEDGE: zz_xrrfix_ledge_grabbing.script + DLTX jump config (specs/fixes/fx-ledge.md)
local H = ...

local MOD, FILE = "zz xrRazom Fix - Ledge Grabbing", "zz_xrrfix_ledge_grabbing"
local LTX = "mod_system_zzzzzzzzzzzzzzz_xrrfix_ledge_jump.ltx"
local XRR_LTX = "mod_system_zzzzzzzzzzzzzz_xrmpe_chemzs_actor.ltx"
local MARKER = "[XRRFIX] ledge: continuous ledge detection restored"
local NOT_FOUND = "[XRRFIX] ledge: Anti-Lag ledge script not found, nothing to do"

-- demonized_ledge_grabbing as shipped by Anti_Lag_for_GAMMA v0.46: the updater is looked
-- up by name inside actor_on_first_update and only checks while jump is held.
local ANTILAG_SRC = [==[
checks = 0
jump_is_being_held = false
function checkLedgeGrabbing() checks = checks + 1 end
function ledge_grabbing_smart_hold_updater()
	if jump_is_being_held then checkLedgeGrabbing() end
end
function actor_on_first_update()
	RegisterScriptCallback("actor_on_update", ledge_grabbing_smart_hold_updater)
end
]==]

-- original Demonized script: registers checkLedgeGrabbing directly
local ORIGINAL_SRC = [==[
checks = 0
function checkLedgeGrabbing() checks = checks + 1 end
function actor_on_first_update()
	RegisterScriptCallback("actor_on_update", checkLedgeGrabbing)
end
]==]

local function setup(src)
	local G = H.env()
	local lg = src and H.load_module(G, "demonized_ledge_grabbing", src) or nil
	local fix = H.load_fix(G, MOD, FILE)
	return G, lg, fix
end

local function updates(G, n)
	for _ = 1, n do G.SendScriptCallback("actor_on_update") end
end

H.case("FX-LEDGE-001 Anti-Lag updater checks on every update without jump held", function()
	local G, lg, fix = setup(ANTILAG_SRC)
	fix.on_game_start()
	lg.actor_on_first_update()
	updates(G, 3)
	H.eq(3, lg.checks, "checkLedgeGrabbing calls")
	H.eq(1, H.log_count(G, MARKER), "install log once")
end)

H.case("FX-LEDGE-001 without the fix Anti-Lag does not check (stub sanity)", function()
	local G, lg = setup(ANTILAG_SRC)
	lg.actor_on_first_update()
	updates(G, 3)
	H.eq(0, lg.checks, "no checks while jump is not held")
end)

H.case("FX-LEDGE-001 repeated level loads do not register the updater twice", function()
	local G, lg, fix = setup(ANTILAG_SRC)
	fix.on_game_start()
	lg.actor_on_first_update()
	lg.actor_on_first_update()
	updates(G, 2)
	H.eq(2, lg.checks, "one call per update")
end)

H.case("FX-LEDGE-002 updater calls the current module checkLedgeGrabbing", function()
	local G, lg, fix = setup(ANTILAG_SRC)
	fix.on_game_start()
	local hits = 0
	lg.checkLedgeGrabbing = function() hits = hits + 1 end
	lg.actor_on_first_update()
	updates(G, 2)
	H.eq(2, hits, "patched function used")
	H.eq(0, lg.checks, "old function not used")
end)

H.case("FX-LEDGE-003 second on_game_start keeps the same updater and logs once", function()
	local G, lg, fix = setup(ANTILAG_SRC)
	fix.on_game_start()
	local f = lg.ledge_grabbing_smart_hold_updater
	fix.on_game_start()
	H.truthy(f == lg.ledge_grabbing_smart_hold_updater, "same function")
	H.eq(1, H.log_count(G, MARKER), "marker once")
end)

H.case("FX-LEDGE-004 original Demonized script is left untouched", function()
	local G, lg, fix = setup(ORIGINAL_SRC)
	local check = lg.checkLedgeGrabbing
	fix.on_game_start()
	H.truthy(lg.checkLedgeGrabbing == check, "checkLedgeGrabbing unchanged")
	H.falsy(rawget(lg, "ledge_grabbing_smart_hold_updater"), "no updater added")
	H.falsy(rawget(lg, "__xrrfix_continuous"), "no flag set")
	H.log_has(G, NOT_FOUND)
	H.log_lacks(G, MARKER)
end)

H.case("FX-LEDGE-004 no Ledge Grabbing module: nothing to do, no error", function()
	local G, _, fix = setup(nil)
	fix.on_game_start()
	H.log_has(G, NOT_FOUND)
end)

H.case("FX-LEDGE-005 error while patching is caught and logged", function()
	local G, _, fix = setup(nil)
	G.demonized_ledge_grabbing = setmetatable({}, { __index = function() error("boom", 0) end })
	fix.on_game_start()
	H.log_has(G, "[XRRFIX] ledge: patch failed: boom")
end)

local function ltx_lines()
	local src = H.read_file(H.root .. "/mods/" .. MOD .. "/gamedata/configs/" .. LTX)
	local out = {}
	for line in (src .. "\n"):gmatch("([^\n]*)\n") do
		line = line:gsub("\r$", ""):gsub(";.*$", ""):match("^%s*(.-)%s*$")
		if line ~= "" then out[#out + 1] = line end
	end
	return out
end

H.case("FX-LEDGE-006 DLTX override of [actor] sets only jump_speed = 6.85", function()
	local lines = ltx_lines()
	H.eq("![actor]", lines[1], "section override")
	H.eq(2, #lines, "one key")
	local k, v = lines[2]:match("^([%w_]+)%s*=%s*(.-)$")
	H.eq("jump_speed", k, "key")
	H.eq("6.85", v, "value")
end)

H.case("FX-LEDGE-006 config file sorts after the xrRazom actor config", function()
	H.truthy(LTX > XRR_LTX, LTX .. " must sort after " .. XRR_LTX)
end)
