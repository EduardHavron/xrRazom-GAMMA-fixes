-- FX-LASER: zz_xrrfix_laser.script (specs/fixes/fx-laser.md)
local H = ...

local MOD, FILE = "zz xrRazom Fix - Laser State", "zz_xrrfix_laser"

-- xrr_item_mdata (xrRazom 1.4): manifest + declare as shipped (plus a call counter).
local IM_SRC = [==[
manifest = {}
declare_calls = 0
function declare(key, opts)
	declare_calls = declare_calls + 1
	for _, d in ipairs(manifest) do
		if d.key == key then
			d.apply = (opts and opts.apply) or d.apply
			return
		end
	end
	manifest[#manifest + 1] = { key = key, apply = opts and opts.apply }
end
]==]

local function count_key(manifest, key)
	local n = 0
	for _, d in ipairs(manifest) do if d.key == key then n = n + 1 end end
	return n
end

local function setup(with_laser, with_mdata)
	local G = H.env()
	if with_laser then G.zzz_bas_laser_control = {} end
	local im = with_mdata and H.load_module(G, "xrr_item_mdata", IM_SRC)
	local fix = H.load_fix(G, MOD, FILE)
	return G, fix, im
end

H.case("FX-LASER-001 saved_lasers_id declared as an item rider", function()
	local G, fix, im = setup(true, true)
	fix.on_game_start()
	H.eq(1, #im.manifest, "manifest size")
	H.eq("saved_lasers_id", im.manifest[1].key, "key")
	H.log_has(G, "[XRRFIX] laser: saved_lasers_id declared as per-item rider")
end)

H.case("FX-LASER-002 second install does not duplicate the key", function()
	local G, fix, im = setup(true, true)
	fix.on_game_start()
	fix.on_game_start()
	H.eq(1, count_key(im.manifest, "saved_lasers_id"), "occurrences")
	H.eq(1, #im.manifest, "manifest size")
end)

H.case("FX-LASER-003 skipped without Laser Settings or without xrr_item_mdata", function()
	local G, fix, im = setup(false, true)
	fix.on_game_start()
	H.log_has(G, "[XRRFIX] laser: Laser Settings not installed, skipped")
	H.eq(0, im.declare_calls, "declare not called")
	H.eq(0, #im.manifest, "manifest untouched")

	G, fix = setup(true, false)
	fix.on_game_start()
	H.log_has(G, "[XRRFIX] laser: xrr_item_mdata.declare missing, skipped")
	H.log_lacks(G, "install error")
end)
