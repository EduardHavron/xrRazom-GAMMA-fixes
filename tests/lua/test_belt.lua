-- FX-BELT: zz_xrrfix_remember_belt.script (specs/fixes/fx-belt.md)
local H = ...

local MOD, FILE = "zz xrRazom Fix - Remember Belt", "zz_xrrfix_remember_belt"

-- xrr_peer_mdata (xrRazom 1.4): manifest / sub_filter / register as shipped (manifest abridged).
local PM_SRC = [==[
manifest = {
	"skills_levels",
	"psy_table",
	"RF_freq",
}
sub_filter = {}
function register(key, subs)
	for _, k in ipairs(manifest) do
		if k == key then
			if subs then sub_filter[key] = subs end
			return
		end
	end
	manifest[#manifest + 1] = key
	sub_filter[key] = subs
end
]==]

-- remember_outfit_belt (G_FLAT): save_belt is called by the item callbacks through the
-- module table (global lookup inside the module).
local RB_SRC = [==[
saved = {}
function save_belt(outfit)
	saved[#saved + 1] = outfit
end
function actor_item_to_belt(item)
	save_belt("outfit_of_" .. tostring(item))
end
]==]

local function setup(session)
	local G = H.env()
	G.XrrIsConnected = function() return session == "peer" end
	G.XrrIsHosted = function() return session == "host" end
	local pm = H.load_module(G, "xrr_peer_mdata", PM_SRC)
	local rb = H.load_module(G, "remember_outfit_belt", RB_SRC)
	local fix = H.load_fix(G, MOD, FILE)
	return G, fix, pm, rb
end

local function count(list, v)
	local n = 0
	for _, x in ipairs(list) do if x == v then n = n + 1 end end
	return n
end

H.case("FX-BELT-001 beltMemory registered once, travels whole", function()
	local G, fix, pm = setup("peer")
	fix.on_game_start()
	fix.on_game_start()
	H.eq(1, count(pm.manifest, "beltMemory"), "beltMemory occurrences")
	H.eq(nil, pm.sub_filter.beltMemory, "no sub filter")
	H.log_has(G, "[XRRFIX] belt: beltMemory registered as peer m_data, save_belt guarded")
end)

H.case("FX-BELT-002 load_state normalizes keys in place", function()
	local G, fix = setup("peer")
	fix.on_game_start()
	local mem = { ["101"] = { items = { ["5"] = true, [6] = true }, date = "12.5" }, bad = 1, [7] = "x" }
	local m = { beltMemory = mem }
	G.SendScriptCallback("load_state", m)
	H.truthy(rawequal(mem, m.beltMemory), "same table identity")
	H.truthy(m.beltMemory[101], "entry under numeric key 101")
	H.same({ [5] = true, [6] = true }, m.beltMemory[101].items, "items")
	H.eq(12.5, m.beltMemory[101].date, "date")
	H.eq(nil, m.beltMemory["101"], "string key removed")
	H.eq(nil, m.beltMemory.bad, "non-numeric key removed")
	H.eq(nil, m.beltMemory[7], "non-table entry removed")
	H.log_has(G, "[XRRFIX] belt: 1 outfit key(s) normalized")
end)

-- The requirement text covers every entry ("items -> { [number] = true }, date -> number").
-- normalize() iterates dup_table(mem), which is a DEEP copy in Anomaly's _g.script, so an
-- entry already under a numeric key is normalized on the copy and the stored entry keeps
-- string item ids / string date.
H.xfail("FX-BELT-002 numeric outfit key: items/date normalized in place",
	"normalize() edits the dup_table deep copy for already-numeric outfit keys", function()
	local G, fix = setup("peer")
	fix.on_game_start()
	local m = { beltMemory = { [200] = { items = { ["9"] = true }, date = "3" } } }
	G.SendScriptCallback("load_state", m)
	H.same({ [9] = true }, m.beltMemory[200].items, "items of numeric-key entry")
	H.eq(3, m.beltMemory[200].date, "date of numeric-key entry")
end)

H.case("FX-BELT-003 save_belt ignored for 10 s after first update in a session", function()
	local G, fix, _, rb = setup("peer")
	fix.on_game_start()
	local T = 50000
	G.__now = T
	G.SendScriptCallback("actor_on_first_update")
	G.__now = T + 5000
	rb.save_belt("A")
	rb.actor_item_to_belt("x")          -- module-internal call goes through the wrapper too
	H.eq(0, #rb.saved, "inside grace: nothing reached the original")
	G.__now = T + 10001
	rb.save_belt("B")
	H.same({ "B" }, rb.saved, "after grace: original called")
end)

H.case("FX-BELT-003 solo: no grace, every save goes through", function()
	local G, fix, _, rb = setup(nil)
	fix.on_game_start()
	G.__now = 50000
	G.SendScriptCallback("actor_on_first_update")
	G.__now = 50001
	rb.save_belt("A")
	rb.actor_item_to_belt("x")
	H.same({ "A", "outfit_of_x" }, rb.saved, "all calls reached the original")
end)
