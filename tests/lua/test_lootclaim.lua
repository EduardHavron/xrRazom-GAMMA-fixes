-- MOD-LOOTCLAIM: grok_loot_claim.script (specs/fixes/mod-lootclaim.md)
local H = ...

-- the mod folder carries the version in its name: take it from pack/pack.json
local MOD = H.read_file(H.root .. "/pack/pack.json"):match('"(Combined GAMMA NPC Loot Claim[^"]*)"')
assert(MOD, "Combined GAMMA NPC Loot Claim not listed in pack/pack.json")

-- position stub: points on the X axis, distance = |dx|
local function pos(x)
	return { x = x, distance_to = function(self, o) return math.abs(self.x - o.x) end }
end

-- game object: kind = "stalker" | "mutant" | "other"
local function body(id, o)
	o = o or {}
	o.id_v = id
	o.name_v = o.name_v or ("obj_" .. id)
	local t = H.obj(o)
	t.kind = o.kind or "stalker"
	t.alive_v = o.alive_v ~= false
	t.x = o.x or 0
	t.infos = o.infos or {}
	t.comm = o.comm or "stalker"
	function t:alive() return self.alive_v end
	function t:has_info(i) return self.infos[i] == true end
	function t:position() return pos(self.x) end
	function t:character_icon() return "icon_" .. self.id_v end
	return t
end

local function setup(opts)
	opts = opts or {}
	local G = H.env()
	local actor = body(0, { name_v = "actor", x = 0 })
	G.db = { actor = actor, storage = {} }
	G.__objects = {}
	G.__vars = {}
	G.__valuable = {}
	G.__msgs = {}
	G.__tips = {}
	G.IsStalker = function(o) return o and o.kind == "stalker" or false end
	G.IsMonster = function(o) return o and o.kind == "mutant" or false end
	G.character_community = function(o) return o.comm end
	G.get_object_story_id = function(id) return (opts.story or {})[id] end
	G.get_story_object = function(sid) return (opts.story_objects or {})[sid] end
	G.load_var = function(obj, key, def) local v = G.__vars[key]; if v == nil then return def end return v end
	G.save_var = function(obj, key, val) G.__vars[key] = val end
	G.level = { object_by_id = function(id) return G.__objects[id] end }
	G.xr_corpse_detection = { set_valuable_loot = function(id, v) G.__valuable[id] = v == nil and "nil" or v end }
	G.key_bindings = { kUSE = 77 }
	G.__ray_target = nil
	G.ray_pick = function()
		local r = {}
		for _, m in ipairs({ "set_flags", "set_range", "set_position", "set_direction", "set_ignore_object", "query" }) do
			r[m] = function() end
		end
		r.get_result = function() if G.__ray_target then return { object = G.__ray_target } end end
		return r
	end
	G.device = function() return { cam_pos = pos(0), cam_dir = pos(1) } end
	G.game = { translate_string = function(s) return s end }
	G.strformat = string.format
	G.round_idp = function(x) return math.floor(x + 0.5) end
	G.dynamic_news_helper = { send_tip = function(msg, header) G.__tips[#G.__tips + 1] = { msg = msg, header = header } end }
	G.actor_menu = { set_msg = function(t, msg, dur) G.__msgs[#G.__msgs + 1] = msg end }
	if opts.mcm then
		G.ui_mcm = { get = function(path) return opts.mcm[(path:gsub("^grok_loot_claim/", ""))] end }
	end
	if opts.peers then
		local dummies = opts.peers
		G.XrrPlayers = function() return { IsPlayerDummy = function(self, id) return dummies[id] == true end } end
	end
	if opts.autolooter then
		G.__al_calls = {}
		G.z_auto_looter = {
			get_actor = function() return G.__al_target end,
			auto_looter = function(key, b) G.__al_calls[#G.__al_calls + 1] = b:id() end,
		}
	end
	local m = H.load_fix(G, MOD, "grok_loot_claim")
	m.on_game_start()
	return G, m
end

local function add(G, o) G.__objects[o:id()] = o; G.db.storage[o:id()] = G.db.storage[o:id()] or {}; return o end
local function kill(G, m, victim, killer)
	victim.alive_v = false
	m.npc_on_death_callback(victim, killer)
end
local function use(G, m, target)
	G.__ray_target = target
	local flags = { ret_value = true }
	m.on_before_key_press(1, G.key_bindings.kUSE, 0, flags)
	return flags.ret_value
end
local function tick(G, m, t) G.__now = t; m.actor_on_update() end
local function saved(G)
	local md = {}
	G.SendScriptCallback("save_state", md)
	return md
end

-------------------------------------------------------------------------------

H.case("MOD-LOOTCLAIM-001 MCM page lists every DEFAULTS key with the same defaults", function()
	local G = H.env()
	local mcm = H.load_fix(G, MOD, "grok_loot_claim_mcm").on_mcm_load()
	H.eq("grok_loot_claim", mcm.id)
	local defs = {}
	for _, e in ipairs(mcm.gr) do if e.def ~= nil then defs[e.id] = e end end
	local expected = {
		enabled = true, player_loot_all = false, npc_loot_all = false, claim_mutants = true, release_killer_dead = true,
		release_killer_far = true, far_distance = 35, release_after_loot = true, release_delay = 10, show_messages = true,
		companions_are_player = true, block_autolooter = true, debug = false,
	}
	local n = 0
	for k, v in pairs(expected) do
		n = n + 1
		H.truthy(defs[k], "MCM option " .. k)
		H.eq(v, defs[k].def, "default of " .. k)
	end
	local cnt = 0
	for _ in pairs(defs) do cnt = cnt + 1 end
	H.eq(n, cnt, "no extra options")
	H.eq(10, defs.far_distance.min); H.eq(150, defs.far_distance.max)
	H.eq(0, defs.release_delay.min); H.eq(60, defs.release_delay.max)
	-- the script's DEFAULTS table carries the same values
	local src = H.read_file(H.root .. "/mods/" .. MOD .. "/gamedata/scripts/grok_loot_claim.script")
	for k, v in pairs(expected) do
		H.truthy(src:find("\n\t" .. k .. "%s*=%s*" .. tostring(v) .. ","), "DEFAULTS." .. k .. " = " .. tostring(v))
	end
end)

H.case("MOD-LOOTCLAIM-001 without MCM defaults apply; MCM enabled=false switches the mod off", function()
	local G, m = setup()
	local v, k = add(G, body(5)), add(G, body(7))
	kill(G, m, v, k)
	H.eq(false, use(G, m, v), "default: claimed and blocked")
	local G2, m2 = setup({ mcm = { enabled = false } })
	local v2, k2 = add(G2, body(5)), add(G2, body(7))
	kill(G2, m2, v2, k2)
	H.eq(true, use(G2, m2, v2), "disabled via MCM: not blocked")
	H.eq(nil, saved(G2).claimed[5], "nothing registered")
end)

H.case("MOD-LOOTCLAIM-002 actor kill of a stalker: tracked and locked for NPCs", function()
	local G, m = setup()
	local v = add(G, body(5))
	G.db.storage[5].corpse_already_selected = 123
	kill(G, m, v, G.db.actor)
	local md = saved(G)
	H.eq(true, md.player_kills[5], "in player_kills")
	H.eq(nil, md.claimed[5], "not claimed")
	H.eq(0, G.db.storage[5].corpse_already_selected, "corpse_already_selected = 0")
	H.eq("nil", G.__valuable[5], "set_valuable_loot(id, nil)")
end)

H.case("MOD-LOOTCLAIM-002 peer avatar (XrrPlayers dummy) and companion count as the player", function()
	local G, m = setup({ peers = { [42] = true } })
	local v1, v2 = add(G, body(5)), add(G, body(6))
	local peer = add(G, body(42))
	local comp = add(G, body(43, { infos = { npcx_is_companion = true } }))
	kill(G, m, v1, peer)
	kill(G, m, v2, comp)
	local md = saved(G)
	H.eq(true, md.player_kills[5], "peer kill")
	H.eq(true, md.player_kills[6], "companion kill")
end)

H.case("MOD-LOOTCLAIM-002 no xrRazom: a non-actor killer is not a peer", function()
	local G, m = setup()
	local v, k = add(G, body(5)), add(G, body(42))
	kill(G, m, v, k)
	H.eq(nil, saved(G).player_kills[5])
	H.eq(42, saved(G).claimed[5], "treated as an NPC kill")
end)

H.case("MOD-LOOTCLAIM-002 npc_loot_all: player kill is not tracked; mutant victim of the player is not locked", function()
	local G, m = setup({ mcm = { npc_loot_all = true } })
	local v = add(G, body(5))
	kill(G, m, v, G.db.actor)
	H.eq(nil, saved(G).player_kills[5])
	local G2, m2 = setup()
	local mut = add(G2, body(8, { kind = "mutant" }))
	kill(G2, m2, mut, G2.db.actor)
	H.eq(nil, saved(G2).player_kills[8], "mutant not tracked")
	H.eq(nil, saved(G2).claimed[8], "mutant not claimed")
	H.eq(nil, G2.__valuable[8], "no lock call")
end)

H.case("MOD-LOOTCLAIM-003 free bodies: no killer, suicide, story npc, zombied, companion (option off), non-stalker killer, mutant (option off)", function()
	local function claimed_after(opts, victim_o, killer_o, victim_id)
		local G, m = setup(opts)
		local v = add(G, body(victim_id or 5, victim_o))
		local k = killer_o and add(G, body(killer_o.id or 7, killer_o)) or nil
		if killer_o == "self" then k = v end
		kill(G, m, v, k)
		return saved(G).claimed[v:id()]
	end
	H.eq(nil, claimed_after({}, {}, nil), "no killer")
	local G, m = setup()
	local v = add(G, body(5)); kill(G, m, v, v)
	H.eq(nil, saved(G).claimed[5], "suicide")
	H.eq(nil, claimed_after({ story = { [5] = "story_5" } }, {}, {}), "story npc")
	H.eq(nil, claimed_after({}, {}, { comm = "zombied" }), "zombied killer")
	H.eq(nil, claimed_after({ mcm = { companions_are_player = false } }, {}, { infos = { npcx_is_companion = true } }), "companion, option off")
	H.eq(nil, claimed_after({}, {}, { kind = "mutant" }), "mutant killer")
	H.eq(nil, claimed_after({ mcm = { claim_mutants = false } }, { kind = "mutant" }, {}), "mutant victim, claim_mutants=false")
	H.eq(7, claimed_after({}, { kind = "mutant" }, {}), "mutant victim claimed by default")
end)

H.case("MOD-LOOTCLAIM-003 companion kill with companions_are_player=false is free, not a player kill", function()
	local G, m = setup({ mcm = { companions_are_player = false } })
	local v = add(G, body(5))
	local c = add(G, body(43, { infos = { npcx_is_companion = true } }))
	kill(G, m, v, c)
	local md = saved(G)
	H.eq(nil, md.player_kills[5]); H.eq(nil, md.claimed[5])
end)

H.case("MOD-LOOTCLAIM-004 NPC kill: claimed[victim] = killer", function()
	local G, m = setup()
	kill(G, m, add(G, body(5)), add(G, body(7)))
	H.eq(7, saved(G).claimed[5])
end)

H.case("MOD-LOOTCLAIM-005 Use on a claimed body near a live killer is blocked", function()
	local G, m = setup()
	local v, k = add(G, body(5, { x = 1 })), add(G, body(7, { x = 10 }))
	kill(G, m, v, k)
	H.eq(false, use(G, m, v), "ret_value=false")
end)

H.case("MOD-LOOTCLAIM-005 release rules: dead killer (claim dropped), killer not loaded, killer farther than far_distance", function()
	local G, m = setup()
	local v, k = add(G, body(5)), add(G, body(7, { x = 10 }))
	kill(G, m, v, k)
	k.alive_v = false
	H.eq(true, use(G, m, v), "dead killer -> allowed")
	H.eq(nil, saved(G).claimed[5], "claim dropped")

	G, m = setup()
	v, k = add(G, body(5)), add(G, body(7, { x = 10 }))
	kill(G, m, v, k)
	G.__objects[7] = nil
	H.eq(true, use(G, m, v), "killer not loaded -> allowed")
	H.eq(7, saved(G).claimed[5], "claim kept")

	G, m = setup()
	v, k = add(G, body(5)), add(G, body(7, { x = 40 }))
	kill(G, m, v, k)
	H.eq(true, use(G, m, v), "40 m > 35 m -> allowed")
	k.x = 30
	H.eq(false, use(G, m, v), "30 m -> blocked")

	G, m = setup({ mcm = { release_killer_far = false, release_killer_dead = false } })
	v, k = add(G, body(5)), add(G, body(7, { x = 100 }))
	kill(G, m, v, k)
	k.alive_v = false
	H.eq(false, use(G, m, v), "both release options off -> blocked")
end)

H.case("MOD-LOOTCLAIM-005 player_loot_all, other keys, live targets, non-creatures and no hit are ignored", function()
	local G, m = setup({ mcm = { player_loot_all = true } })
	local v, k = add(G, body(5)), add(G, body(7, { x = 5 }))
	kill(G, m, v, k)
	H.eq(true, use(G, m, v), "player_loot_all")

	G, m = setup()
	v, k = add(G, body(5)), add(G, body(7, { x = 5 }))
	kill(G, m, v, k)
	G.__ray_target = v
	local flags = { ret_value = true }
	m.on_before_key_press(1, 99, 0, flags)
	H.eq(true, flags.ret_value, "other key")
	local live = add(G, body(9))
	H.eq(true, use(G, m, live), "live target")
	local box = add(G, body(10, { kind = "other", alive_v = false }))
	H.eq(true, use(G, m, box), "not a stalker/mutant")
	H.eq(true, use(G, m, nil), "ray hit nothing")
end)

H.case("MOD-LOOTCLAIM-006 lock re-applied every 1000 ms while enabled", function()
	local G, m = setup()
	local v = add(G, body(5))
	kill(G, m, v, G.db.actor)
	tick(G, m, 1000)
	G.db.storage[5].corpse_already_selected = nil
	tick(G, m, 1500)
	H.eq(nil, G.db.storage[5].corpse_already_selected, "not before the interval")
	tick(G, m, 2000)
	H.eq(0, G.db.storage[5].corpse_already_selected, "re-locked")
end)

H.case("MOD-LOOTCLAIM-007 opening own kill releases it for NPCs after release_delay", function()
	local G, m = setup()
	local v = add(G, body(5))
	kill(G, m, v, G.db.actor)
	G.__now = 5000
	H.eq(true, use(G, m, v), "player may open own kill")
	tick(G, m, 14000)
	H.eq(true, saved(G).player_kills[5], "still locked before 10 s")
	H.eq(0, G.db.storage[5].corpse_already_selected)
	tick(G, m, 15000)
	H.eq(nil, saved(G).player_kills[5], "released")
	H.eq(nil, G.db.storage[5].corpse_already_selected, "corpse_already_selected = nil")
	H.eq(true, G.__valuable[5], "set_valuable_loot(id, true)")
end)

H.case("MOD-LOOTCLAIM-007 release is scheduled once; release_after_loot=false never releases", function()
	local G, m = setup()
	local v = add(G, body(5))
	kill(G, m, v, G.db.actor)
	G.__now = 1000; use(G, m, v)
	G.__now = 9000; use(G, m, v) -- second open does not move the deadline
	tick(G, m, 11000)
	H.eq(nil, saved(G).player_kills[5], "released at first deadline")

	G, m = setup({ mcm = { release_after_loot = false } })
	v = add(G, body(5))
	kill(G, m, v, G.db.actor)
	G.__now = 1000; use(G, m, v)
	tick(G, m, 100000)
	H.eq(true, saved(G).player_kills[5], "never released")
end)

H.case("MOD-LOOTCLAIM-008 disabling (enabled=false or npc_loot_all) releases every locked body", function()
	local mcm = {}
	local G, m = setup({ mcm = mcm })
	local a, b = add(G, body(5)), add(G, body(6))
	kill(G, m, a, G.db.actor); kill(G, m, b, G.db.actor)
	mcm.enabled = false
	tick(G, m, 1000)
	local md = saved(G)
	H.eq(nil, md.player_kills[5]); H.eq(nil, md.player_kills[6])
	H.eq(true, G.__valuable[5]); H.eq(nil, G.db.storage[6].corpse_already_selected)
	kill(G, m, add(G, body(7)), add(G, body(8)))
	H.eq(nil, saved(G).claimed[7], "no new registrations while disabled")

	mcm = {}
	G, m = setup({ mcm = mcm })
	a = add(G, body(5)); kill(G, m, a, G.db.actor)
	mcm.npc_loot_all = true
	tick(G, m, 1000)
	H.eq(nil, saved(G).player_kills[5], "npc_loot_all releases too")
end)

H.case("MOD-LOOTCLAIM-009 NPC looting a claimed body frees it for the player; player kills untouched", function()
	local G, m = setup()
	local v, k = add(G, body(5)), add(G, body(7, { x = 5 }))
	kill(G, m, v, k)
	local own = add(G, body(6))
	kill(G, m, own, G.db.actor)
	m.npc_on_get_all_from_corpse(k, v, nil, true)
	m.npc_on_get_all_from_corpse(k, own, nil, true)
	local md = saved(G)
	H.eq(nil, md.claimed[5], "claim removed")
	H.eq(true, md.player_kills[6], "player kill stays")
	H.eq(true, use(G, m, v), "player may loot now")

	G, m = setup({ mcm = { release_after_loot = false } })
	v, k = add(G, body(5)), add(G, body(7, { x = 5 }))
	kill(G, m, v, k)
	m.npc_on_get_all_from_corpse(k, v, nil, true)
	H.eq(7, saved(G).claimed[5], "kept with release_after_loot=false")
end)

H.case("MOD-LOOTCLAIM-010 autolooter: blocked body -> get_actor nil + message, auto_looter skipped", function()
	local G, m = setup({ autolooter = true })
	local v, k = add(G, body(5)), add(G, body(7, { x = 5 }))
	kill(G, m, v, k)
	G.__al_target = v
	H.eq(nil, G.z_auto_looter.get_actor(), "get_actor -> nil")
	H.eq("st_npc_loot_claim_far", G.__msgs[#G.__msgs], "message")
	G.z_auto_looter.auto_looter("key", v)
	H.eq(0, #G.__al_calls, "original auto_looter not called")
end)

H.case("MOD-LOOTCLAIM-010 autolooter: allowed body passes and schedules the release of own kill", function()
	local G, m = setup({ autolooter = true })
	local own = add(G, body(6))
	kill(G, m, own, G.db.actor)
	G.__now = 2000
	G.__al_target = own
	H.eq(own, G.z_auto_looter.get_actor(), "passes through")
	G.z_auto_looter.auto_looter("key", own)
	H.eq(1, #G.__al_calls, "original called")
	tick(G, m, 12000)
	H.eq(nil, saved(G).player_kills[6], "release scheduled by the autolooter open")
end)

H.case("MOD-LOOTCLAIM-010 block_autolooter=false passes everything; no z_auto_looter -> no error", function()
	local G, m = setup({ autolooter = true, mcm = { block_autolooter = false } })
	local v, k = add(G, body(5)), add(G, body(7, { x = 5 }))
	kill(G, m, v, k)
	G.__al_target = v
	H.eq(v, G.z_auto_looter.get_actor())
	G.z_auto_looter.auto_looter("key", v)
	H.eq(1, #G.__al_calls)
	local G2, m2 = setup()
	H.eq(nil, rawget(G2, "z_auto_looter"), "no autolooter module")
	kill(G2, m2, add(G2, body(5)), G2.db.actor)
end)

H.case("MOD-LOOTCLAIM-011 block message: tip from a near killer, actor_menu text otherwise; show_messages=false silent", function()
	local G, m = setup()
	local v, k = add(G, body(5)), add(G, body(7, { x = 10, name_v = "Killer" }))
	kill(G, m, v, k)
	use(G, m, v)
	H.eq(1, #G.__tips, "tip sent")
	H.truthy(G.__tips[1].msg:match("^st_npc_loot_claim_last_[1-5]$"), "random last_1..5: " .. G.__tips[1].msg)
	H.truthy(G.__tips[1].header:find("Killer", 1, true), "header names the killer")

	G, m = setup({ mcm = { release_killer_far = false } })
	v, k = add(G, body(5)), add(G, body(7, { x = 30 }))
	kill(G, m, v, k)
	use(G, m, v)
	H.eq(0, #G.__tips, "killer farther than 25 m -> no tip")
	H.eq("st_npc_loot_claim_far", G.__msgs[1])

	G, m = setup({ mcm = { show_messages = false } })
	v, k = add(G, body(5)), add(G, body(7, { x = 5 }))
	kill(G, m, v, k)
	H.eq(false, use(G, m, v), "still blocked")
	H.eq(0, #G.__tips); H.eq(0, #G.__msgs)
end)

H.case("MOD-LOOTCLAIM-012 save/load round trip; pending is not saved", function()
	local G, m = setup()
	kill(G, m, add(G, body(5)), add(G, body(7)))
	local own = add(G, body(6))
	kill(G, m, own, G.db.actor)
	G.__now = 1000; use(G, m, own)
	local md = saved(G)
	H.eq(7, md.claimed[5]); H.eq(true, md.player_kills[6])
	H.truthy(md.loot_claim_seq and md.loot_claim_seq.c and md.loot_claim_seq.p and md.loot_claim_seq.n == 2, "seq saved")
	H.eq(nil, md.pending, "pending not saved")

	local G2, m2 = setup()
	G2.SendScriptCallback("load_state", { claimed = { [5] = 7 }, player_kills = { [6] = true } })
	local back = saved(G2)
	H.eq(7, back.claimed[5]); H.eq(true, back.player_kills[6])
	tick(G2, m2, 100000)
	H.eq(true, saved(G2).player_kills[6], "no pending after load -> stays locked")

	local G3 = setup()
	G3.SendScriptCallback("load_state", {})
	local empty = saved(G3)
	H.eq(nil, next(empty.claimed)); H.eq(nil, next(empty.player_kills)); H.eq(0, empty.loot_claim_seq.n)
end)

H.case("MOD-LOOTCLAIM-013 level change clears all tables", function()
	local G, m = setup()
	kill(G, m, add(G, body(5)), add(G, body(7)))
	kill(G, m, add(G, body(6)), G.db.actor)
	m.on_level_changing()
	local md = saved(G)
	H.eq(nil, next(md.claimed)); H.eq(nil, next(md.player_kills))
end)

H.case("MOD-LOOTCLAIM-014 over 1000 entries the 100 oldest are dropped", function()
	local G, m = setup()
	local killer = add(G, body(99999))
	for i = 1, 1001 do
		local v = body(i)
		G.__objects[i] = v
		kill(G, m, v, killer)
	end
	local md = saved(G)
	local n = 0
	for _ in pairs(md.claimed) do n = n + 1 end
	H.eq(901, n, "1001 - 100")
	H.eq(nil, md.claimed[1], "oldest dropped"); H.eq(nil, md.claimed[100])
	H.eq(99999, md.claimed[101], "101 kept"); H.eq(99999, md.claimed[1001], "newest kept")
end)

H.case("MOD-LOOTCLAIM-015 Semenov tissue counter: actor mutant kills only, independent of enabled", function()
	local opts = { story_objects = { yan_ecolog_semenov = {} }, mcm = { enabled = false } }
	local G, m = setup(opts)
	G.__vars.yan_ecolog_semenov_task_1_tissue_need = 3
	kill(G, m, add(G, body(5, { kind = "mutant" })), G.db.actor)
	kill(G, m, add(G, body(6, { kind = "mutant" })), G.db.actor)
	H.eq(2, G.__vars.yan_ecolog_semenov_task_1_tissue_count, "two actor kills")
	kill(G, m, add(G, body(7, { kind = "mutant" })), add(G, body(8)))
	kill(G, m, add(G, body(9)), G.db.actor)
	H.eq(2, G.__vars.yan_ecolog_semenov_task_1_tissue_count, "NPC kill and stalker victim do not count")

	G, m = setup({ story_objects = { yan_ecolog_semenov = {} } })
	kill(G, m, add(G, body(5, { kind = "mutant" })), G.db.actor)
	H.eq(nil, G.__vars.yan_ecolog_semenov_task_1_tissue_count, "need = 0 -> no count")

	G, m = setup()
	G.__vars.yan_ecolog_semenov_task_1_tissue_need = 3
	kill(G, m, add(G, body(5, { kind = "mutant" })), G.db.actor)
	H.eq(nil, G.__vars.yan_ecolog_semenov_task_1_tissue_count, "no Semenov -> no count")
end)

H.case("MOD-LOOTCLAIM callbacks registered on game start", function()
	local G = setup()
	for _, n in ipairs({ "npc_on_death_callback", "monster_on_death_callback", "npc_on_get_all_from_corpse",
		"on_before_key_press", "actor_on_update", "save_state", "load_state", "on_level_changing" }) do
		H.eq(1, #H.callbacks(G, n), n)
	end
end)
