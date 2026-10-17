-- FX-QLIST: zz_xrrfix_quest_queue.script (specs/fixes/fx-qlist.md)
local H = ...

local MOD, FILE = "zz xrRazom Fix - Taskboard Refresh", "zz_xrrfix_quest_queue"
local MARKER = "[XRRFIX] questq: OnQuestListRequest queued on host (budget 8 ms per update)"

-- xrr_patch_quests (xrRazom 1.4) defines OnQuestListRequest as a module function and exports
-- it to _G at file end; loaded lazily, so the fix must force-load it. Each call records its
-- arguments and advances the fake clock by cost[npc] ms (default 3).
local QUESTS_SRC = [==[
calls = {}
cost = {}
function OnQuestListRequest(conn, npc, ...)
	calls[#calls + 1] = { conn = conn, npc = npc, n = select("#", ...) + 2 }
	__advance(cost[npc] or 3)
	if npc == "boom" then error("generate failed", 0) end
	return "ret"
end
_G.OnQuestListRequest = OnQuestListRequest
]==]

local function setup(opts)
	opts = opts or {}
	local G = H.env()
	G.__us = 0
	G.__advance = function(ms) G.__us = G.__us + ms * 1000 end
	if opts.os_clock then
		G.os = { clock = function() return G.__us / 1e6 end }
	else
		G.profile_timer = function()
			local t = { acc = 0 }
			function t:start() self.t0 = G.__us end
			function t:stop() self.acc = self.acc + (G.__us - self.t0) end
			function t:time() return self.acc end
			return t
		end
	end
	G.XrrIsHost = function() return opts.host ~= false end
	if not opts.no_quests then H.lazy(G, "xrr_patch_quests", QUESTS_SRC) end
	local fix = H.load_fix(G, MOD, FILE)
	fix.on_game_start()
	return G, rawget(G, "xrr_patch_quests"), fix
end

local function req(G, conn, npc) return G.OnQuestListRequest(conn, npc) end
local function update(G) G.SendScriptCallback("actor_on_update") end
local function npcs(q)
	local out = {}
	for i, c in ipairs(q.calls) do out[i] = c.npc end
	return out
end

H.case("FX-QLIST-001 force-loads xrr_patch_quests, wraps once, logs the marker", function()
	local G, q, fix = setup()
	H.truthy(q, "xrr_patch_quests force-loaded")
	H.truthy(G.OnQuestListRequest ~= q.OnQuestListRequest, "_G handler replaced")
	local w = G.OnQuestListRequest
	fix.on_game_start()
	H.truthy(G.OnQuestListRequest == w, "second on_game_start keeps the same wrapper")
	H.eq(1, H.log_count(G, MARKER), "marker once")
	req(G, 1, 10)
	H.same({ 10 }, npcs(q), "one call reaches the original (no double wrap)")
end)

H.case("FX-QLIST-001 without the handler: logged and skipped", function()
	local G = setup({ no_quests = true })
	H.log_has(G, "[XRRFIX] questq: _G.OnQuestListRequest missing, skipped")
	H.log_lacks(G, MARKER)
	H.falsy(rawget(G, "OnQuestListRequest"), "nothing installed")
end)

H.case("FX-QLIST-002 peer: every call passes straight through with all arguments", function()
	local G, q = setup({ host = false })
	for i = 1, 5 do H.eq("ret", G.OnQuestListRequest(1, i, "x"), "return value kept") end
	H.same({ 1, 2, 3, 4, 5 }, npcs(q), "all run at once")
	H.eq(3, q.calls[1].n, "extra argument passed")
	update(G)
	H.eq(5, #q.calls, "nothing queued")
end)

H.case("FX-QLIST-003 lone request on the host runs at once", function()
	local G, q = setup()
	req(G, 1, 10)
	H.same({ 10 }, npcs(q), "ran immediately")
	update(G)
	req(G, 1, 11)
	H.same({ 10, 11 }, npcs(q), "next window: immediate again")
	H.log_lacks(G, "requests (", "no batch summary for lone requests")
end)

H.case("FX-QLIST-004 burst: first runs, the rest wait for actor_on_update", function()
	local G, q = setup()
	for i = 1, 5 do req(G, 1, i) end
	H.same({ 1 }, npcs(q), "only the first ran")
	update(G)
	H.same({ 1, 2, 3, 4 }, npcs(q), "3 ms each: 3 more within 8 ms, FIFO")
end)

H.case("FX-QLIST-005 budget: stops at 8 ms, at least one per update", function()
	local G, q = setup()
	req(G, 1, 0)
	for i = 1, 4 do req(G, 1, i) end
	update(G)
	H.same({ 0, 1, 2, 3 }, npcs(q), "3 of 4 queued run (0, 3, 6 ms < 8)")
	update(G)
	H.same({ 0, 1, 2, 3, 4 }, npcs(q), "last one next update")

	G, q = setup()
	q.cost[1], q.cost[2], q.cost[3] = 50, 50, 50
	req(G, 1, 0)
	req(G, 1, 1); req(G, 1, 2); req(G, 1, 3)
	update(G)
	H.same({ 0, 1 }, npcs(q), "a 50 ms request: one per update")
	update(G); update(G)
	H.same({ 0, 1, 2, 3 }, npcs(q), "drained one by one")
end)

H.case("FX-QLIST-005 os.clock fallback without profile_timer", function()
	local G, q = setup({ os_clock = true })
	req(G, 1, 0)
	for i = 1, 4 do req(G, 1, i) end
	update(G)
	H.same({ 0, 1, 2, 3 }, npcs(q), "same budget with os.clock")
end)

H.case("FX-QLIST-006 duplicates of queued requests are dropped and counted", function()
	local G, q = setup()
	req(G, 1, 0)
	req(G, 1, 5); req(G, 1, 5); req(G, 2, 5); req(G, 1, 6); req(G, 1, 6)
	update(G)
	H.same({ 0, 5, 5, 6 }, npcs(q), "(1,5) and (1,6) once each, (2,5) is another peer")
	H.log_has(G, "[XRRFIX] questq: 4 requests (2 duplicates) over 1 updates, total 12 ms, max 3 ms")
end)

H.case("FX-QLIST-007 one summary line per drained burst", function()
	local G, q = setup()
	q.cost[3] = 20
	for i = 1, 4 do req(G, 1, i) end
	update(G)
	H.eq(0, H.log_count(G, "requests ("), "queue not empty yet: no summary")
	update(G)
	H.log_has(G, "[XRRFIX] questq: 4 requests (0 duplicates) over 2 updates, total 29 ms, max 20 ms")
	update(G)
	H.eq(1, H.log_count(G, "requests ("), "no repeat when idle")
end)

H.case("FX-QLIST-008 original error is logged, the queue keeps draining", function()
	local G, q = setup()
	req(G, 1, 0)
	req(G, 1, "boom"); req(G, 1, 2)
	update(G)
	H.same({ 0, "boom", 2 }, npcs(q), "request after the failing one still ran")
	H.log_has(G, "[XRRFIX] questq: request error: generate failed")
end)

H.case("FX-QLIST-008 level change drops the queue without running it", function()
	local G, q = setup()
	for i = 1, 4 do req(G, 1, i) end
	G.SendScriptCallback("on_level_changing")
	H.log_has(G, "[XRRFIX] questq: level change, 3 queued requests dropped")
	update(G)
	H.same({ 1 }, npcs(q), "queued requests never ran")
	req(G, 1, 9)
	H.same({ 1, 9 }, npcs(q), "fresh window after the clear: immediate")
end)
