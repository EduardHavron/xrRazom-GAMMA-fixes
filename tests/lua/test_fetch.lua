-- FX-FETCH: zz_xrrfix_fetch_reward.script (specs/fixes/fx-fetch.md)
local H = ...

local MOD, FILE = "zz xrRazom Fix - Fetch Reward", "zz_xrrfix_fetch_reward"

-- xrr_quest_reward.calc_fetch_money as shipped in xrRazom 1.4 (plus a call counter).
local QR_SRC = [==[
orig_calls = 0
function calc_fetch_money(task_id)
    orig_calls = orig_calls + 1
    local raw_oc = task_manager.task_ini:r_string_ex(task_id, "on_complete")
    if not raw_oc then return 0 end
    local fetch_var, fetch_mult = raw_oc:match("fetch_reward_and_remove%(([^:%)]+):?([%d%.]*)")
    if not fetch_var then return 0 end
    local sec = utils_data.load_var(db.actor, fetch_var)
    local count = utils_data.load_var(db.actor, task_id .. "_fetch_count") or 1
    if not (sec and ini_sys:section_exist(sec)) then return 0 end
    local multi = game_difficulties.get_eco_factor("rewards") or 1
    local cost = ini_sys:r_float_ex(sec, "cost") or 500
    local total = cost * count * multi * (tonumber(fetch_mult) or 1)
    local delta_r = math.floor(total * 0.1)
    return math.random(math.floor(total - delta_r), math.floor(total + delta_r))
end
]==]

local TASK = "simulation_task_23"
local VAR = TASK .. "_fetch"

-- opts: sections = { sec = {cost=, class=, max_uses=, kind=} }, sec, count, mult,
--       on_complete, host_items, host_belt, peers = { {nick=, id=, items=, belt=} }, eco_type
local function setup(opts)
	local G = H.env()
	G.utils_data = H.utils_data(G)
	local sections = opts.sections or { pelt = { cost = 1000, class = "II_ATTCH" } }
	G.ini_sys = H.ini(sections)
	G.__eco = { type = opts.eco_type or 1, rewards = 7 }
	G.game_difficulties = { get_eco_factor = function(k) return G.__eco[k] end }
	G.task_manager = {
		task_ini = H.ini({ [TASK] = { on_complete = opts.on_complete or
			("%=fetch_reward_and_remove(" .. VAR .. (opts.mult and (":" .. opts.mult) or "") .. ")%") } }),
	}
	G.__pstor[VAR] = opts.sec or "pelt"
	G.__pstor[VAR .. "_count"] = opts.count
	-- Anomaly helpers over the section ini
	G.IsItem = function(kind, sec)
		local s = sections[sec] or {}
		if kind == "multiuse" then
			local n = tonumber(s.max_uses)
			return n and n > 1 and n or nil
		end
		return s.kind == kind
	end
	G.IsArtefact = function(obj)
		local s = sections[obj:section()] or {}
		return string.find(s.class or "", "^ART") ~= nil
	end
	G.__se = {}
	G.se_load_var = function(id, name, key) return G.__se[id] and G.__se[id][key] end

	local function owner(id, items, belt)
		local inv = {}
		for _, it in ipairs(items or {}) do inv[#inv + 1] = it end
		for _, it in ipairs(belt or {}) do inv[#inv + 1] = it end   -- belt items are in the inventory too
		return H.obj({ id_v = id, inventory = inv, belt = belt or {} })
	end
	G.db = { actor = owner(0, opts.host_items, opts.host_belt) }
	local objects = {}
	if opts.peers then
		local list = {}
		for _, p in ipairs(opts.peers) do
			objects[p.id] = owner(p.id, p.items, p.belt)
			list[#list + 1] = p
		end
		-- XrrPlayers() registry API used by the fix (xrr_core)
		G.XrrPlayers = function()
			return {
				GetPeerCount = function(self) return #list end,
				GetPeerLocalIdAt = function(self, i) return list[i].id end,
				GetPeerNicknameAt = function(self, i) return list[i].nick end,
			}
		end
	end
	G.level = { object_by_id = function(id) return objects[id] end }

	local qr = H.load_module(G, "xrr_quest_reward", QR_SRC)
	local fix = H.load_fix(G, MOD, FILE)
	fix.on_game_start()
	H.log_has(G, "[XRRFIX] fetch: calc_fetch_money patched (host reads peer avatars)", "install log")
	return G, qr
end

local next_id = 1000
local function item(sec, cond, extra)
	next_id = next_id + 1
	local o = extra or {}
	o.id_v, o.section_v, o.condition_v = next_id, sec, cond or 1
	return H.obj(o)
end

local function roll_is(rec, v, tol, msg)
	local lo, hi = H.roll_bounds(v)
	H.truthy(rec, (msg or "") .. ": math.random called")
	if math.abs(rec.lo - lo) > tol or math.abs(rec.hi - hi) > tol then
		error(string.format("%s: roll bounds [%s, %s], expected [%s, %s] (v=%s)",
			msg or "roll", tostring(rec.lo), tostring(rec.hi), lo, hi, v), 2)
	end
end

H.case("FX-FETCH-001 inventory_value matches the Tasks QoL formula (condition^2)", function()
	local G, qr = setup({ count = 2, host_items = { item("pelt", 0.5), item("pelt", 1.0) } })
	local rec = H.record_random(G)
	qr.calc_fetch_money(TASK)
	roll_is(rec[1], 1250, 0, "1000*0.25 + 1000*1")
	H.log_has(G, "[XRRFIX] fetch: " .. TASK .. " host items pelt x2 -> ")
	H.eq(0, qr.orig_calls, "original not used")
end)

H.case("FX-FETCH-001 artefact class with eco type 3 -> x0.4", function()
	local G, qr = setup({ count = 2, eco_type = 3,
		sections = { af_pelt = { cost = 1000, class = "ARTEFACT" } }, sec = "af_pelt",
		host_items = { item("af_pelt", 0.5), item("af_pelt", 1.0) } })
	local rec = H.record_random(G)
	qr.calc_fetch_money(TASK)
	roll_is(rec[1], 500, 0, "1250 * 0.4")
end)

H.case("FX-FETCH-001 weapon condition = mean of prt_w_* parts / 100", function()
	local w = item("wpn_x", 0.1, { weapon_type = 2 })
	local G, qr = setup({ count = 1, sections = { wpn_x = { cost = 1000, class = "WP_TOZ34" } }, sec = "wpn_x",
		host_items = { w } })
	G.__se[w:id()] = { parts = { prt_w_a = 80, prt_w_b = 60, other = 10 } }
	local rec = H.record_random(G)
	qr.calc_fetch_money(TASK)
	roll_is(rec[1], 1000 * 0.7 * 0.7, 1, "cost * 0.49 (con 0.7, not condition() 0.1)")
end)

H.case("FX-FETCH-002 belt items do not count -> not enough -> nil (falls to nominal)", function()
	local G, qr = setup({ count = 2, host_items = { item("pelt", 1) }, host_belt = { item("pelt", 1) } })
	local rec = H.record_random(G)
	qr.calc_fetch_money(TASK)
	H.log_lacks(G, "host items", "host does not hold enough without the belt")
	H.log_has(G, "[XRRFIX] fetch: " .. TASK .. " no holder reachable, nominal pelt x2 -> ")
	roll_is(rec[1], 2000, 0, "nominal")
end)

H.case("FX-FETCH-002 multiuse: cost/max_use * remaining uses, no condition", function()
	local G, qr = setup({ count = 2, sections = { kit = { cost = 300, max_uses = 3 } }, sec = "kit",
		host_items = { item("kit", 0.5, { uses = 2 }) } })
	local rec = H.record_random(G)
	qr.calc_fetch_money(TASK)
	roll_is(rec[1], 200, 0, "300/3*2")
	H.log_has(G, "host items kit x2")
end)

H.case("FX-FETCH-002 sum below 50 is raised to 50", function()
	local G, qr = setup({ count = 1, sections = { cheap = { cost = 40 } }, sec = "cheap",
		host_items = { item("cheap", 1) } })
	local rec = H.record_random(G)
	qr.calc_fetch_money(TASK)
	roll_is(rec[1], 50, 0, "min 50")
end)

H.case("FX-FETCH-003 host items first", function()
	-- host: 2000 * 0.5 = 1000; peer A: 2000 * 1 = 2000
	local G, qr = setup({ count = 1, sections = { pelt = { cost = 2000 } },
		host_items = { item("pelt", math.sqrt(0.5)) },
		peers = { { nick = "A", id = 11, items = { item("pelt", 1) } } } })
	local v = qr.calc_fetch_money(TASK)
	H.between(900, 1100, v, "host value 1000 rolled")
	H.log_has(G, "[XRRFIX] fetch: " .. TASK .. " host items pelt x1 -> " .. v)
	H.log_lacks(G, "items of")
end)

H.case("FX-FETCH-003 best peer avatar when the host lacks items", function()
	local G, qr = setup({ count = 1, sections = { pelt = { cost = 1250 } },
		peers = {
			{ nick = "A", id = 11, items = { item("pelt", 0.8) } },               -- ~800
			{ nick = "B", id = 12, items = { item("pelt", math.sqrt(0.96)) } },  -- ~1200
			{ nick = "C", id = 13, items = {} },                                 -- holds nothing
		} })
	local v = qr.calc_fetch_money(TASK)
	H.between(1080, 1320, v, "B's value rolled")
	H.log_has(G, "[XRRFIX] fetch: " .. TASK .. " items of B pelt x1 -> " .. v)
	H.log_lacks(G, "host items")
end)

H.case("FX-FETCH-003 no holder -> nominal cost*count*mult", function()
	local G, qr = setup({ count = 2, mult = "1.5", sections = { pelt = { cost = 1000 } },
		peers = { { nick = "A", id = 11, items = { item("pelt", 1) } } } })
	local v = qr.calc_fetch_money(TASK)
	H.between(2700, 3300, v, "nominal 1000*2*1.5")
	H.log_has(G, "[XRRFIX] fetch: " .. TASK .. " no holder reachable, nominal pelt x2 -> " .. v)
	H.eq(0, qr.orig_calls, "original not used")
end)

H.case("FX-FETCH-003 on_complete without fetch_reward_and_remove -> original", function()
	local G, qr = setup({ count = 1, on_complete = "%=reward_random_money(100:200)%", host_items = { item("pelt", 1) } })
	local v = qr.calc_fetch_money(TASK)
	H.eq(1, qr.orig_calls, "original called once")
	H.eq(0, v, "original's result returned")
	H.log_lacks(G, "fetch: " .. TASK)
end)

H.case("FX-FETCH-004 both completion calls pay > 0 from the same holder", function()
	local G, qr = setup({ count = 1, sections = { pelt = { cost = 500 } }, host_items = { item("pelt", 1) } })
	local a = qr.calc_fetch_money(TASK)   -- peers' share
	local b = qr.calc_fetch_money(TASK)   -- host credit
	H.between(450, 550, a, "first call")
	H.between(450, 550, b, "second call")
	H.truthy(a ~= 0 and b ~= 0, "no zero credit")
	H.eq(2, H.log_count(G, "fetch: " .. TASK .. " host items pelt x1 -> "), "same source twice")
end)
