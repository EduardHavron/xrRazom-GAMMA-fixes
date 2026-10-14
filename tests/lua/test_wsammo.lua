-- FX-WSAMMO: zz_workshop_ammo_fix.script (specs/fixes/fx-wsammo.md)
local H = ...

local MOD, FILE = "zz Workshop Ammo Material Fix", "zz_workshop_ammo_fix"

-- ui_workshop.UIWorkshopCraft with the Craft From Stashes Craft (release part of
-- 471- Craft From Stashes/zz_ui_workshop_keep_crafting_window_open.script) and an
-- UpdateItem that only records its calls.
local UW_SRC = [==[
UIWorkshopCraft = {}

function UIWorkshopCraft.UpdateItem(self, n, sec, amount, result)
	update_calls[#update_calls + 1] = { n = n, sec = sec, amount = amount, result = result }
end

function UIWorkshopCraft.Craft(self)
	craft_calls[#craft_calls + 1] = { complexCraft = dup_table(self.complexCraft or {}) }
	if (not self.craft_allow_r) then
		return
	end
	local complexCraftingSections = {}
	if self.complexCraft and #self.complexCraft > 0 then
		for _, ccInfo in pairs(self.complexCraft) do
			alife_release_id(ccInfo.id1)
			alife_release_id(ccInfo.id2)
			if ccInfo.newItemSize >= 1 then
				local stashId = self.stashId or (self.owner and self.owner.stashId)
				if stashId then
					alife_create_item(ccInfo.section, get_object_by_id(stashId), {ammo = ccInfo.newItemSize})
				else
					alife_create_item(ccInfo.section, db.actor, {ammo = ccInfo.newItemSize})
				end
			end
			complexCraftingSections[ccInfo.section] = true
		end
	end
	for i=1,#self.craft_item do
		if #self.craft_item[i] > 0 then
			for j=1,#self.craft_item[i] do
				local itm = get_object_by_id(self.craft_item[i][j])
				if itm then
					local itmSect = itm:section()
					if complexCraftingSections[itmSect] then
						complexCraftingSections[itmSect] = nil
					else
						alife_release_id(self.craft_item[i][j])
					end
				else
					alife_release_id(self.craft_item[i][j])
				end
			end
		end
	end
end
update_calls = {}
craft_calls = {}
]==]

local function setup()
	local G = H.env()
	G.db = { actor = H.obj({ id_v = 0, name_v = "actor" }) }
	G.__released, G.__created, G.__objects = {}, {}, {}
	G.alife_release_id = function(id) G.__released[#G.__released + 1] = id end
	G.alife_create_item = function(sec, parent, t)
		G.__created[#G.__created + 1] = { sec = sec, parent = parent, t = t }
	end
	G.get_object_by_id = function(id) return G.__objects[id] end
	for _, id in ipairs({ 11, 12, 13, 21, 22 }) do
		G.__objects[id] = H.obj({ id_v = id, section_v = "ammo_x" })
	end
	local uw = H.load_module(G, "ui_workshop", UW_SRC)
	local fix = H.load_fix(G, MOD, FILE)
	fix.on_game_start()
	G.SendScriptCallback("actor_on_first_update")
	H.log_has(G, "[WSFIX] workshop: ammo material consumption patched", "install log")
	local cls = uw.UIWorkshopCraft
	local inst = setmetatable({}, { __index = cls })
	return G, uw, inst, fix
end

local function sorted(list)
	local c = {}
	for i, v in ipairs(list) do c[i] = v end
	table.sort(c)
	return c
end

local function cc(size)
	return { id1 = 21, id2 = 22, section = "ammo_x", newItemSize = size }
end

H.case("FX-WSAMMO-001 fewer full boxes than needed: partials and ALL full boxes consumed", function()
	local G, uw, inst = setup()
	inst:UpdateItem(1, "ammo_x", 3, false)
	H.same({ sec = "ammo_x", amount = 3 }, inst.__xrrfix_need[1], "__xrrfix_need[1]")
	H.eq(1, #uw.update_calls, "original UpdateItem called")
	inst.craft_allow_r = true
	inst.craft_item = { { 11, 12 } }
	inst.complexCraft = { cc(5) }
	inst:Craft()
	H.same({ 11, 12, 21, 22 }, sorted(G.__released), "released ids")
	H.eq(1, #G.__created, "one remainder box")
	H.eq("ammo_x", G.__created[1].sec)
	H.same({ ammo = 5 }, G.__created[1].t)
	H.truthy(rawequal(G.db.actor, G.__created[1].parent), "created on the actor (no stash)")
	H.eq(1, #uw.craft_calls, "original Craft called")
	H.same({}, uw.craft_calls[1].complexCraft, "entry removed before the original ran")
	H.log_has(G, "[WSFIX] workshop: ammo_x merged partials handled, 2/3 full boxes consumed normally")
end)

H.case("FX-WSAMMO-002 enough full boxes: complexCraft left to the original", function()
	local G, uw, inst = setup()
	inst:UpdateItem(1, "ammo_x", 2, false)
	inst.craft_allow_r = true
	inst.craft_item = { { 11, 12 } }
	inst.complexCraft = { cc(5) }
	inst:Craft()
	H.same({ cc(5) }, uw.craft_calls[1].complexCraft, "complexCraft passed unchanged")
	H.log_lacks(G, "merged partials handled")
	-- original behaviour: one full box "replaced" by the partial pair
	H.same({ 12, 21, 22 }, sorted(G.__released), "original release pattern")
end)

H.case("FX-WSAMMO-003 newItemSize < 1: partials released, no remainder created", function()
	local G, uw, inst = setup()
	inst:UpdateItem(1, "ammo_x", 3, false)
	inst.craft_allow_r = true
	inst.craft_item = { { 11, 12 } }
	inst.complexCraft = { cc(0) }
	inst:Craft()
	H.eq(0, #G.__created, "alife_create_item not called")
	H.same({ 11, 12, 21, 22 }, sorted(G.__released), "released ids")
end)

H.case("FX-WSAMMO-004 craft not allowed / empty complexCraft: wrapper does nothing", function()
	local G, uw, inst = setup()
	inst:UpdateItem(1, "ammo_x", 3, false)
	inst.craft_allow_r = false
	inst.craft_item = { { 11, 12 } }
	inst.complexCraft = { cc(5) }
	inst:Craft()
	H.eq(1, #uw.craft_calls, "original called")
	H.eq(0, #G.__released, "nothing released")
	H.eq(0, #G.__created, "nothing created")
	H.eq(1, #inst.complexCraft, "complexCraft untouched")
	H.log_lacks(G, "merged partials handled")

	G, uw, inst = setup()
	inst:UpdateItem(1, "ammo_x", 3, false)
	inst.craft_allow_r = true
	inst.craft_item = { { 11, 12 } }
	inst.complexCraft = {}
	inst:Craft()
	H.eq(0, #G.__created, "nothing created")
	H.same({ 11, 12 }, sorted(G.__released), "only the original's releases")
	H.log_lacks(G, "merged partials handled")
end)

H.case("FX-WSAMMO-005 wrappers installed once per class", function()
	local G = H.env()
	G.db = { actor = H.obj({ id_v = 0 }) }
	local uw = H.load_module(G, "ui_workshop", UW_SRC)
	local orig_update, orig_craft = uw.UIWorkshopCraft.UpdateItem, uw.UIWorkshopCraft.Craft
	-- two loads of the fix in one VM, both registered for actor_on_first_update
	H.load_fix(G, MOD, FILE).on_game_start()
	H.load_fix(G, MOD, FILE).on_game_start()
	G.SendScriptCallback("actor_on_first_update")
	local w_update, w_craft = uw.UIWorkshopCraft.UpdateItem, uw.UIWorkshopCraft.Craft
	G.SendScriptCallback("actor_on_first_update")
	H.eq(1, H.log_count(G, "ammo material consumption patched"), "installed once")
	H.eq(true, uw.UIWorkshopCraft.__xrrfix_wrapped, "flag")
	H.truthy(w_update ~= orig_update and w_craft ~= orig_craft, "wrapped")
	H.truthy(rawequal(w_update, uw.UIWorkshopCraft.UpdateItem) and rawequal(w_craft, uw.UIWorkshopCraft.Craft),
		"not re-wrapped")
	local inst = setmetatable({}, { __index = uw.UIWorkshopCraft })
	inst:UpdateItem(1, "ammo_x", 3, false)
	H.eq(1, #uw.update_calls, "one original UpdateItem call per call (single wrapper layer)")
end)
