-- FX-KILLTR: zz_xrrfix_kill_tracker.script (specs/fixes/fx-killtr.md)
local H = ...

local MOD, FILE = "zz xrRazom Fix - Kill Tracker Mirror Corpses", "zz_xrrfix_kill_tracker"

-- ish_kill_tracker (413- Milspec PDA): new_kill / new_silent_kill / on_game_start
-- registration shape as shipped; bodies reduced to recording.
local KT_SRC = [==[
kills = {}
silent_fail = false
function new_kill(victim, killer)
	kills[#kills + 1] = victim:id()
end
function new_silent_kill(victim, killer, weapon, was_melee)
	if not (victim and killer) then return end
	new_kill(victim, killer)
	if silent_fail then error("silent boom", 0) end
end
function on_game_start()
	RegisterScriptCallback("npc_on_death_callback", new_kill)
	RegisterScriptCallback("monster_on_death_callback", new_kill)
	if AddScriptCallback and stealth_kill_detection then
		RegisterScriptCallback("npc_on_silent_kill_callback", new_silent_kill)
	end
end
]==]

local function setup(opts)
	opts = opts or {}
	local G = H.env()
	G.__peer = opts.peer ~= false
	G.XrrIsClient = function() return G.__peer end
	G.db = { actor = H.obj({ id_v = 0, name_v = "actor" }) }
	if opts.stealth then
		G.stealth_kill_detection = {}
		G.AddScriptCallback("npc_on_silent_kill_callback")
	end
	local kt = H.load_module(G, "ish_kill_tracker", KT_SRC)
	local orig_kill, orig_silent = kt.new_kill, kt.new_silent_kill
	if opts.mod_first ~= false then kt.on_game_start() end
	local fix = H.load_fix(G, MOD, FILE)
	fix.on_game_start()
	if opts.mod_first == false then kt.on_game_start() end
	H.log_has(G, "[XRRFIX] killtracker: mirror corpse guard installed", "install log")
	return G, kt, orig_kill, orig_silent
end

local function npc(id) return H.obj({ id_v = id, name_v = "npc_" .. id }) end

H.case("FX-KILLTR-001 peer: actor kill without a hit is not recorded", function()
	local G, kt = setup()
	kt.new_kill(npc(500), G.db.actor)
	H.eq(0, #kt.kills, "original not called")
	H.log_has(G, "[XRRFIX] killtracker: npc_500 (500) died without a hit from this player -> not his kill")
end)

H.case("FX-KILLTR-001 skip log limited to 5 per session", function()
	local G, kt = setup()
	for i = 1, 7 do kt.new_kill(npc(600 + i), G.db.actor) end
	H.eq(0, #kt.kills, "none recorded")
	H.eq(5, H.log_count(G, "died without a hit from this player"), "log lines")
end)

H.case("FX-KILLTR-002 hit within 60 s counts, mark cleared; after 60 s it does not", function()
	local G, kt = setup()
	local v = npc(500)
	G.__now = 100000
	G.SendScriptCallback("npc_on_hit_callback", v, 10, nil, G.db.actor)
	G.__now = 100000 + 59000
	kt.new_kill(v, G.db.actor)
	H.same({ 500 }, kt.kills, "recorded")
	kt.new_kill(v, G.db.actor)
	H.same({ 500 }, kt.kills, "last_hit[500] cleared: a second death without a new hit is dropped")

	G, kt = setup()
	G.__now = 100000
	G.SendScriptCallback("npc_on_hit_callback", v, 10, nil, G.db.actor)
	G.__now = 100000 + 61000
	kt.new_kill(v, G.db.actor)
	H.eq(0, #kt.kills, "outside the window: not recorded")
end)

H.case("FX-KILLTR-002 hit via npc_on_before_hit draftsman / monster callbacks", function()
	local G, kt = setup()
	G.__now = 5000
	G.SendScriptCallback("npc_on_before_hit", npc(501), { draftsman = G.db.actor })
	G.SendScriptCallback("monster_on_hit_callback", npc(502), 3, nil, G.db.actor)
	G.SendScriptCallback("monster_on_before_hit", npc(503), { draftsman = G.db.actor })
	G.SendScriptCallback("npc_on_hit_callback", npc(504), 3, nil, npc(7))   -- someone else's hit
	G.__now = 20000
	for _, id in ipairs({ 501, 502, 503, 504 }) do kt.new_kill(npc(id), G.db.actor) end
	H.same({ 501, 502, 503 }, kt.kills, "actor hits count, a foreign hit does not")
end)

H.case("FX-KILLTR-003 silent kill passes, flag reset after return and after error", function()
	local G, kt = setup()
	kt.new_silent_kill(npc(500), G.db.actor)
	H.same({ 500 }, kt.kills, "new_kill from inside new_silent_kill recorded")
	kt.new_kill(npc(501), G.db.actor)
	H.same({ 500 }, kt.kills, "in_silent reset after return")

	kt.silent_fail = true
	local ok, err = pcall(kt.new_silent_kill, npc(502), G.db.actor)
	H.falsy(ok, "original's error propagates")
	H.truthy(string.find(tostring(err), "silent boom", 1, true), "same error: " .. tostring(err))
	H.same({ 500, 502 }, kt.kills, "recorded before the error")
	kt.new_kill(npc(503), G.db.actor)
	H.same({ 500, 502 }, kt.kills, "in_silent reset after error")
end)

H.case("FX-KILLTR-004 host/solo and non-actor killers always reach the original", function()
	local G, kt = setup({ peer = false })
	kt.new_kill(npc(500), G.db.actor)
	H.same({ 500 }, kt.kills, "not a peer")

	G, kt = setup()
	kt.new_kill(npc(501), H.obj({ id_v = 7, name_v = "host_avatar" }))
	kt.new_kill(npc(502), npc(300))
	H.same({ 501, 502 }, kt.kills, "host avatar / NPC killer")
end)

local function check_registry(G, kt, orig_kill, orig_silent, stealth)
	for _, cb in ipairs({ "npc_on_death_callback", "monster_on_death_callback" }) do
		local list = H.callbacks(G, cb)
		H.eq(1, #list, cb .. " registrations")
		H.truthy(rawequal(list[1], kt.new_kill), cb .. " -> wrapper")
		H.truthy(not rawequal(list[1], orig_kill), cb .. " original not registered")
	end
	if stealth then
		local list = H.callbacks(G, "npc_on_silent_kill_callback")
		H.eq(1, #list, "silent registrations")
		H.truthy(rawequal(list[1], kt.new_silent_kill) and not rawequal(list[1], orig_silent), "silent -> wrapper")
	end
	-- a mirror corpse through the death callback is dropped, a real kill recorded once
	G.SendScriptCallback("npc_on_death_callback", npc(900), G.db.actor)
	H.eq(0, #kt.kills, "mirror dropped via callback")
	G.__now = 1000
	G.SendScriptCallback("npc_on_hit_callback", npc(901), 1, nil, G.db.actor)
	G.SendScriptCallback("npc_on_death_callback", npc(901), G.db.actor)
	H.same({ 901 }, kt.kills, "wrapper called once")
end

H.case("FX-KILLTR-005 (a) mod registered first: original swapped for the wrapper", function()
	local G, kt, ok_, os_ = setup({ mod_first = true, stealth = true })
	check_registry(G, kt, ok_, os_, true)
end)

H.case("FX-KILLTR-005 (b) mod registers after the fix: picks up the wrapper", function()
	local G, kt, ok_, os_ = setup({ mod_first = false, stealth = true })
	check_registry(G, kt, ok_, os_, true)
end)
