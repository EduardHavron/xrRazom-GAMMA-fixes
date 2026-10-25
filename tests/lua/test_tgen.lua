-- FX-TGEN: zz_xrrfix_tgen.script, zz_xrrfix_tgen_prof.script (specs/fixes/fx-tgen.md)
local H = ...

local MOD = "zz Task Generation Speed Fix"
local FIX, PROF = "zz_xrrfix_tgen", "zz_xrrfix_tgen_prof"
local MEMO_MARKER = "[XRRFIX] tgen: prerequisites memo installed (5000 ms)"
local BOUNTY_MARKER = "[XRRFIX] tgen: bounty scan shared (snapshot 5000 ms)"
local BOUNTY_SKIP = "[XRRFIX] tgen: Taskboard bounty selector not found, bounty part skipped"

-- Stand-in for PDA Taskboard Redesign v1.3 z_taskboard_bounty_variants.script: the same local
-- names and call shapes (GetVariantInfo -> variant_list -> build_variants and its helpers), with
-- fake server objects { stalker, alive, comm, rela, map, near, bad_smart }. build_variants is
-- the original full scan; Variants(task_id, p) is a test entry that reaches it like
-- setup_bounty_task does. __valid_calls counts candidate_valid; __reject makes it refuse ids.
local BOUNTY_SRC = [==[
local MAX_VARIANTS = 3
local faction_list = { "stalker", "dolg", "freedom", "bandit", "army" }
local blacklisted_maps = { ["l13_generators"] = true, ["fake_start"] = true }

local function selected_blacklist() return __extra_blacklist end
local function is_smart_valid(squad_id) return not (__bad_smarts and __bad_smarts[squad_id]) end
local function level_of(se_obj) return se_obj and se_obj.map end
local function faction_lookup_from_params(p)
	local lookup = {}
	if p[2] == "true" then
		for i = 1, #faction_list do
			if faction_list[i] ~= p[4] then lookup[faction_list[i]] = true end
		end
	else
		for i = 4, #p do lookup[p[i]] = true end
	end
	return lookup
end
local function candidate_relation(id, se_obj, faction_lookup)
	if not (id and se_obj and se_obj.stalker and se_obj.alive) then return end
	if faction_lookup[alife_character_community(se_obj)] ~= true then return end
	return se_obj.rela
end
local function candidate_valid(id, p)
	__valid_calls = (__valid_calls or 0) + 1
	if __reject and __reject[id] then return false end
	local se_obj = alife_object(id)
	return candidate_relation(id, se_obj, faction_lookup_from_params(p)) ~= nil
end
local function append_unique(result, seen, source)
	if #result >= MAX_VARIANTS then return true end
	for _, id in ipairs(source or {}) do
		if not seen[id] then
			seen[id] = true
			result[#result + 1] = id
			if #result >= MAX_VARIANTS then return true end
		end
	end
	return false
end
local function shuffled_copy(source)
	local result = {}
	for _, v in ipairs(source or {}) do result[#result + 1] = v end
	return result
end
local function build_variants(task_id, p)
	local faction_lookup = faction_lookup_from_params(p)
	local valid = { enemy = {}, neutral = {} }
	local other = { enemy = {}, neutral = {} }
	local additional_blacklist = selected_blacklist()
	local sim = alife()
	for id = 1, 65534 do
		local se_obj = sim:object(id)
		if se_obj then
			local relation = candidate_relation(id, se_obj, faction_lookup)
			if relation and is_smart_valid(se_obj.group_id) then
				local map = level_of(se_obj)
				if map and not blacklisted_maps[map] and not (additional_blacklist and additional_blacklist[map]) then
					if p[3] == "true" and not simulation_objects.is_on_the_nearby_level(sim:actor(), se_obj) then
						other[relation][#other[relation] + 1] = id
					else
						valid[relation][#valid[relation] + 1] = id
					end
				end
			end
		end
	end
	local result, seen = {}, {}
	if append_unique(result, seen, shuffled_copy(valid.enemy)) then return result end
	if append_unique(result, seen, shuffled_copy(valid.neutral)) then return result end
	if append_unique(result, seen, shuffled_copy(other.enemy)) then return result end
	append_unique(result, seen, shuffled_copy(other.neutral))
	return result
end
local function variant_list(task_id, p)
	if not candidate_valid then return {} end
	return build_variants(task_id, p)
end
function GetVariantInfo(task_id) return variant_list(task_id) end
function Variants(task_id, p) return variant_list(task_id, p) end
]==]

-- world: id -> fake server object; counts alife():object calls
local function make_world(G, objs)
	G.__objects = 0
	local sim = {}
	function sim:object(id) G.__objects = G.__objects + 1; return objs[id] end
	function sim:actor() return { id = 0 } end
	G.alife = function() return sim end
	G.alife_object = function(id) return objs[id] end
	G.alife_character_community = function(se) return se.comm end
	G.simulation_objects = { is_on_the_nearby_level = function(_, se) return se.near end }
end

local function st(comm, rela, map, near, extra)
	local o = { stalker = true, alive = true, comm = comm, rela = rela, map = map or "l01_escape", near = near ~= false, group_id = 500 }
	for k, v in pairs(extra or {}) do o[k] = v end
	return o
end

local function setup(opts)
	opts = opts or {}
	local G = H.env()
	G.__prereq = {}
	G.xr_conditions = opts.no_prereq and {} or {
		has_completed_task_prerequisites = function(actor, npc, p, extra)
			G.__prereq[#G.__prereq + 1] = { actor = actor, npc = npc, id = p and p[1], extra = extra }
			return (G.__answers or {})[p and p[1]] ~= false
		end,
	}
	make_world(G, opts.objs or {})
	if opts.debug then G.debug = opts.debug end
	if not opts.no_bounty then
		local src = BOUNTY_SRC
		if opts.bounty_patch then src = opts.bounty_patch(src) end
		H.lazy(G, "z_taskboard_bounty_variants", src)
	end
	local fix = H.load_fix(G, MOD, FIX)
	fix.on_game_start()
	return G, fix
end

local function prereq(G, id) return G.xr_conditions.has_completed_task_prerequisites(nil, nil, { id }) end
local function variants(G, task_id, p) return G.z_taskboard_bounty_variants.Variants(task_id, p) end

---------------------------------------------------------------------------
-- memo
---------------------------------------------------------------------------

H.case("FX-TGEN-001 wraps has_completed_task_prerequisites once and logs the marker", function()
	local G, fix = setup()
	local w = G.xr_conditions.has_completed_task_prerequisites
	fix.on_game_start()
	H.truthy(G.xr_conditions.has_completed_task_prerequisites == w, "second on_game_start keeps the wrapper")
	H.eq(1, H.log_count(G, MEMO_MARKER), "marker once")
	prereq(G, "t1")
	H.eq(1, #G.__prereq, "one call reaches the original (no double wrap)")
end)

H.case("FX-TGEN-001 without the function: logged and skipped", function()
	local G = setup({ no_prereq = true })
	H.log_has(G, "[XRRFIX] tgen: has_completed_task_prerequisites missing, memo skipped")
	H.log_lacks(G, MEMO_MARKER)
	H.falsy(G.xr_conditions.has_completed_task_prerequisites, "nothing installed")
end)

H.case("FX-TGEN-002 generation calls answered from the memo for 5000 ms, per task_id", function()
	local G = setup()
	G.__answers = { t1 = false }
	H.eq(false, prereq(G, "t1"), "original result")
	G.__now = 4999
	H.eq(false, prereq(G, "t1"), "memo result")
	H.eq(1, #G.__prereq, "original called once within 5000 ms")
	H.eq(true, prereq(G, "t2"), "other task_id: own result")
	H.eq(2, #G.__prereq, "other task_id asks the original")
	G.__now = 5000
	G.__answers = { t1 = true }
	H.eq(true, prereq(G, "t1"), "fresh result after 5000 ms")
	H.eq(3, #G.__prereq, "original called again at 5000 ms")
end)

H.case("FX-TGEN-003 calls with an actor, an npc or no task id always reach the original", function()
	local G = setup()
	local f = G.xr_conditions.has_completed_task_prerequisites
	f("actor", nil, { "t1" })
	f("actor", nil, { "t1" })
	f(nil, "npc", { "t1" }, "x")
	f(nil, nil, {})
	f(nil, nil, { 5 })
	H.eq(5, #G.__prereq, "all five reached the original")
	H.eq("actor", G.__prereq[1].actor, "actor passed")
	H.eq("npc", G.__prereq[3].npc, "npc passed")
	H.eq("x", G.__prereq[3].extra, "extra argument passed")
	prereq(G, "t1")
	H.eq(6, #G.__prereq, "logic calls stored nothing")
end)

H.case("FX-TGEN-004 on_level_changing clears the memo and the bounty snapshot", function()
	local G = setup({ objs = { [10] = st("bandit", "enemy") } })
	prereq(G, "t1")
	variants(G, "b1", { "b1", "false", "false", "bandit" })
	H.eq(65534, G.__objects, "one scan")
	G.SendScriptCallback("on_level_changing")
	prereq(G, "t1")
	H.eq(2, #G.__prereq, "memo cleared")
	variants(G, "b1", { "b1", "false", "false", "bandit" })
	H.eq(2 * 65534, G.__objects, "snapshot cleared, scanned again")
end)

---------------------------------------------------------------------------
-- bounty
---------------------------------------------------------------------------

H.case("FX-TGEN-005 swaps build_variants once and logs the marker", function()
	local G, fix = setup({ objs = { [10] = st("bandit", "enemy") } })
	H.eq(1, H.log_count(G, BOUNTY_MARKER), "marker")
	fix.on_game_start()
	H.eq(1, H.log_count(G, BOUNTY_MARKER), "marker once")
	variants(G, "b1", { "b1", "false", "false", "bandit" })
	variants(G, "b2", { "b2", "false", "false", "bandit" })
	H.eq(65534, G.__objects, "the shared scan is in place")
end)

H.case("FX-TGEN-005 without the module, debug or a helper: logged and skipped", function()
	local G = setup({ no_bounty = true })
	H.log_has(G, BOUNTY_SKIP)
	H.log_lacks(G, BOUNTY_MARKER)
	H.log_has(G, MEMO_MARKER, "memo still installed")

	G = setup({ debug = {} })
	H.log_has(G, BOUNTY_SKIP, "no debug library")

	G = setup({ objs = { [10] = st("bandit", "enemy") },
		bounty_patch = function(src) return (string.gsub(src, "local MAX_VARIANTS = 3", "MAX_VARIANTS = 3")) end })
	H.log_has(G, BOUNTY_SKIP, "helper missing")
	H.log_lacks(G, BOUNTY_MARKER)
	variants(G, "b1", { "b1", "false", "false", "bandit" })
	variants(G, "b2", { "b2", "false", "false", "bandit" })
	H.eq(2 * 65534, G.__objects, "original build_variants untouched")
end)

H.case("FX-TGEN-006 one scan per 5000 ms snapshot", function()
	local G = setup({ objs = { [10] = st("bandit", "enemy"), [20] = st("army", "enemy"), [30] = st("dolg", "neutral") } })
	variants(G, "b1", { "b1", "false", "false", "bandit" })
	variants(G, "b2", { "b2", "false", "false", "army" })
	G.__now = 4999
	variants(G, "b3", { "b3", "false", "false", "dolg" })
	H.eq(65534, G.__objects, "three tasks, one scan")
	G.__now = 5000
	variants(G, "b4", { "b4", "false", "false", "dolg" })
	H.eq(2 * 65534, G.__objects, "new scan after 5000 ms")
	local s = G.zz_xrrfix_tgen.take_stats()
	H.eq(2, s.built, "two snapshots built")
	H.eq(2, s.reused, "two reused")
end)

H.case("FX-TGEN-007 picks the same candidates, in the same group order, as the original", function()
	local objs = {
		[1] = st("bandit", "enemy", "l01_escape", false),        -- far enemy
		[2] = st("stalker", "neutral", "l01_escape", true),      -- other faction
		[3] = st("bandit", "neutral", "l02_garbage", true),      -- near neutral
		[4] = st("bandit", "enemy", "l03_agroprom", true),       -- near enemy
		[5] = st("bandit", "enemy", "l13_generators", true),     -- blacklisted map
		[6] = st("bandit", "enemy", "l04_darkvalley", true),     -- extra blacklist
		[7] = st("bandit", "enemy", "l01_escape", true, { group_id = 77 }), -- base smart
		[8] = st("bandit", "enemy", "l01_escape", true, { alive = false }),
	}
	local G = setup({ objs = objs })
	G.__extra_blacklist = { l04_darkvalley = true }
	G.__bad_smarts = { [77] = true }
	local p = { "b1", "false", "true", "bandit" }
	H.same({ 4, 3, 1 }, variants(G, "b1", p), "near enemy, near neutral, far enemy")
	H.same({ 1, 4, 3 }, variants(G, "b2", { "b2", "false", "false", "bandit" }), "p[3] false: enemies first")
	H.same({ 2 }, variants(G, "b3", { "b3", "false", "false", "stalker" }), "stalker task sees only stalkers")

	-- the original over the same world
	local O = setup({ objs = objs, debug = {} })
	O.__extra_blacklist = { l04_darkvalley = true }
	O.__bad_smarts = { [77] = true }
	H.same({ 4, 3, 1 }, variants(O, "b1", p), "original agrees")
end)

H.case("FX-TGEN-007 stops at MAX_VARIANTS", function()
	local objs = {}
	for i = 1, 6 do objs[i] = st("bandit", "enemy") end
	local G = setup({ objs = objs })
	H.eq(3, #variants(G, "b1", { "b1", "false", "false", "bandit" }), "three variants")
end)

H.case("FX-TGEN-008 every pick passes candidate_valid; refused ones are replaced", function()
	local objs = { [1] = st("bandit", "enemy"), [2] = st("bandit", "enemy"), [3] = st("bandit", "enemy"), [4] = st("bandit", "enemy") }
	local G = setup({ objs = objs })
	G.__reject = { [2] = true }
	H.same({ 1, 3, 4 }, variants(G, "b1", { "b1", "false", "false", "bandit" }), "2 skipped, 4 takes its place")
	H.eq(4, G.z_taskboard_bounty_variants.__valid_calls, "each pick checked")
	objs[3].alive = false
	G.__reject = nil
	H.same({ 1, 2, 4 }, variants(G, "b2", { "b2", "false", "false", "bandit" }), "dead since the snapshot: skipped")
end)

---------------------------------------------------------------------------
-- profiler
---------------------------------------------------------------------------

local function prof_setup(opts)
	opts = opts or {}
	local G = H.env()
	G.__us = 0
	G.__advance = function(ms) G.__us = G.__us + ms * 1000 end
	G.profile_timer = function()
		local t = { acc = 0 }
		function t:start() self.t0 = G.__us end
		function t:stop() self.acc = self.acc + (G.__us - self.t0) end
		function t:time() return self.acc end
		return t
	end
	G.axr_task_manager = {
		generate_available_tasks = function(npc)
			G.__advance(2)
			G.xr_conditions.validate_assault_task(nil, npc, { "a" })
			return "gen", npc
		end,
	}
	G.xr_conditions = {
		validate_assault_task = function() G.__advance(opts.assault_ms or 3) return true end,
		squad_exist = function() return true end,
	}
	G.xr_effects = {
		setup_bounty_task = function() G.__advance(1) error("bounty failed", 0) end,
	}
	if opts.tgen then
		G.zz_xrrfix_tgen = { take_stats = function() return { hits = 7, misses = 3, built = 1, reused = 4 } end }
	end
	local prof = H.load_fix(G, MOD, PROF)
	prof.on_game_start()
	return G, prof
end

local function first_update(G) G.SendScriptCallback("actor_on_first_update") end
local function update(G) G.SendScriptCallback("actor_on_update") end

H.case("FX-TGEN-009 wraps on actor_on_first_update once; results and errors pass through", function()
	local G = prof_setup()
	H.truthy(G.axr_task_manager.generate_available_tasks, "present")
	local orig = G.xr_conditions.squad_exist
	first_update(G)
	H.log_has(G, "[XRRFIX] taskprof: installed (3 functions timed)")
	H.truthy(G.xr_conditions.squad_exist == orig, "generic logic condition not wrapped")
	local w = G.axr_task_manager.generate_available_tasks
	first_update(G)
	H.truthy(G.axr_task_manager.generate_available_tasks == w, "wrapped once")
	H.eq(1, H.log_count(G, "taskprof: installed"), "marker once")
	local a, b = G.axr_task_manager.generate_available_tasks("npc1")
	H.eq("gen", a, "first result")
	H.eq("npc1", b, "second result")
	local ok, err = pcall(G.xr_effects.setup_bounty_task)
	H.falsy(ok, "error re-raised")
	H.eq("bounty failed", err, "same error")
end)

H.case("FX-TGEN-010 summary after 1 s idle: totals, nested time inside callers, top list", function()
	local G = prof_setup({ tgen = true })
	first_update(G)
	G.axr_task_manager.generate_available_tasks("n1")
	G.axr_task_manager.generate_available_tasks("n2")
	G.__now = 500
	update(G)
	H.log_lacks(G, "taskprof: 0.0 s", "no summary before 1 s idle")
	G.__now = 999
	update(G)
	H.eq(0, H.log_count(G, "| memo"), "still nothing at 999 ms")
	G.__now = 1000
	update(G)
	H.log_has(G, "[XRRFIX] taskprof: 0.0 s, generate 2 calls 10 ms | memo 7/10 hits, bounty snapshots 1 built, 4 reused")
	H.log_has(G, "[XRRFIX] taskprof: #1 axr_task_manager.generate_available_tasks | total 10.0 ms | calls 2 | max 5.0 ms")
	H.log_has(G, "[XRRFIX] taskprof: #2 xr_conditions.validate_assault_task | total 6.0 ms | calls 2 | max 3.0 ms")
	local n = #G.__log
	G.__now = 3000
	update(G)
	H.eq(n, #G.__log, "counters reset: nothing more")
end)

H.case("FX-TGEN-010 under 5 ms (nested time counted once): no summary, counters reset", function()
	local G = prof_setup({ assault_ms = 2 })   -- generate 4 ms, of which assault 2 ms
	first_update(G)
	G.axr_task_manager.generate_available_tasks("n1")
	G.__now = 1000
	update(G)
	H.eq(0, H.log_count(G, "taskprof: #"), "no top list")
	H.eq(0, H.log_count(G, "generate 1 calls"), "no summary")
	G.__now = 1500
	G.axr_task_manager.generate_available_tasks("n2")
	G.axr_task_manager.generate_available_tasks("n3")
	G.axr_task_manager.generate_available_tasks("n4")
	G.__now = 2500
	update(G)
	H.log_has(G, "generate 3 calls 12 ms | no tgen counters", "only the new burst counted")
end)
