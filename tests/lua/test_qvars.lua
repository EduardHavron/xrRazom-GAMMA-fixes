-- FX-QVARS: zz_xrrfix_quest_vars.script (specs/fixes/fx-qvars.md)
local H = ...

local MOD, FILE = "zz xrRazom Fix - Quest Vars Sync", "zz_xrrfix_quest_vars"

-- Stand-in for xrRazom Co-op/gamedata/scripts/xrr_quest_serialize.script (1.4):
-- the var/msg/data (de)serializers as shipped. serialize_quest_data calls
-- serialize_quest_vars as a module global, i.e. through the module table.
local QS_SRC = [==[
function serialize_quest_vars(vars)
    if not vars or not next(vars) then return "" end
    local parts = {}
    for k, v in pairs(vars) do
        local t = type(v)
        if t == "string" then
            parts[#parts + 1] = tostring(k) .. "\ts\t" .. v
        elseif t == "number" then
            parts[#parts + 1] = tostring(k) .. "\tn\t" .. tostring(v)
        elseif t == "boolean" then
            parts[#parts + 1] = tostring(k) .. "\tb\t" .. (v and "1" or "0")
        elseif t == "table" then
            local ok, js = pcall(utils_data.write_to_ini_str, v)
            if ok and js then
                parts[#parts + 1] = tostring(k) .. "\tt\t" .. js
            end
        end
    end
    return table.concat(parts, "\n")
end

function deserialize_quest_vars(blob)
    if not blob or blob == "" then return end
    for line in blob:gmatch("[^\n]+") do
        local key, vtype, val = line:match("^(.+)\t(.)\t(.*)$")
        if key and vtype then
            if vtype == "s" then
                utils_data.save_var(db.actor, key, val)
            elseif vtype == "n" then
                utils_data.save_var(db.actor, key, tonumber(val))
            elseif vtype == "b" then
                utils_data.save_var(db.actor, key, val == "1")
            elseif vtype == "t" then
                local ok, tbl = pcall(utils_data.read_from_ini_str, val)
                if ok and tbl and type(tbl) == "table" then
                    utils_data.save_var(db.actor, key, tbl)
                end
            end
        end
    end
end

function serialize_quest_msgs(msgs)
    if not msgs or not next(msgs) then return "" end
    local parts = {}
    for tid, m in pairs(msgs) do
        parts[#parts + 1] = table.concat({
            tostring(tid), m.caption or "", m.text or "", m.icon or "", m.templ or ""
        }, "\t")
    end
    return table.concat(parts, "\n")
end

function deserialize_quest_msgs(blob)
    local out = {}
    if not blob or blob == "" then return out end
    for line in blob:gmatch("[^\n]+") do
        local tid, caption, text, icon, templ =
            line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
        if tid and tid ~= "" then
            out[tid] = { caption = caption, text = text, icon = icon,
                         templ = (templ ~= "" and templ) or "iconed_answer_item" }
        end
    end
    return out
end

function serialize_quest_data(available, ongoing, vars, msgs)
    return table.concat({
        table.concat(available or {}, ","),
        table.concat(ongoing or {}, ","),
        serialize_quest_vars(vars),
        serialize_quest_msgs(msgs),
    }, "\3")
end

function deserialize_quest_data(blob)
    if not blob or blob == "" then return {}, {}, "", {} end
    local a_str, o_str, v_str, m_str = blob:match("^([^\3]*)\3([^\3]*)\3([^\3]*)\3(.*)$")
    if not a_str then return {}, {}, "", {} end
    local available = {}
    if a_str ~= "" then
        for id in a_str:gmatch("[^,]+") do available[#available + 1] = id end
    end
    local ongoing = {}
    if o_str ~= "" then
        for id in o_str:gmatch("[^,]+") do ongoing[#ongoing + 1] = id end
    end
    return available, ongoing, v_str or "", deserialize_quest_msgs(m_str or "")
end
]==]

local function setup(marshal)
	local G = H.env()
	G.marshal = marshal or H.marshal()
	G.utils_data = H.utils_data(G)
	G.db = { actor = H.obj({ id_v = 0 }) }
	local qs = H.load_module(G, "xrr_quest_serialize", QS_SRC)
	local fix = H.load_fix(G, MOD, FILE)
	fix.on_game_start()
	H.log_has(G, "[XRRFIX] serializer: patched (tables via marshal+hex)", "install log")
	return G, qs
end

local function lines_of(blob)
	local set = {}
	for line in string.gmatch(blob, "[^\n]+") do set[line] = true end
	return set
end

H.case("FX-QVARS-001 table var round-trips to an equal table via save_var", function()
	local G, qs = setup()
	local src = { t1 = { target_id = 123, nested = { a = "x" } } }
	qs.deserialize_quest_vars(qs.serialize_quest_vars(src))
	local got, found = H.saved(G, "t1")
	H.truthy(found, "save_var called for t1")
	H.eq("table", type(got), "t1 type")
	H.same({ target_id = 123, nested = { a = "x" } }, got, "t1 content")
	H.log_has(G, "[XRRFIX] deserialize: 1 table var(s) applied")
end)

H.case("FX-QVARS-002 scalars keep the s/n/b types and round-trip", function()
	local G, qs = setup()
	local blob = qs.serialize_quest_vars({ a = "abc", b = 1.5, c = true, d = false })
	H.same({ ["a\ts\tabc"] = true, ["b\tn\t1.5"] = true, ["c\tb\t1"] = true, ["d\tb\t0"] = true },
		lines_of(blob), "blob lines")
	qs.deserialize_quest_vars(blob)
	H.eq("abc", (H.saved(G, "a")), "a")
	H.eq(1.5, (H.saved(G, "b")), "b")
	H.eq(true, (H.saved(G, "c")), "c")
	local d, found = H.saved(G, "d")
	H.truthy(found, "d saved")
	H.eq(false, d, "d")
	H.log_lacks(G, "table var(s) applied", "no table applied for scalars")
end)

H.case("FX-QVARS-003 control chars travel as hex through serialize_quest_data", function()
	local G, qs = setup()
	local s = "line1\nline2\tx\3y"
	local blob = qs.serialize_quest_data({}, {}, { s = s }, {})
	local _, etx = string.gsub(blob, "\3", "")
	H.eq(3, etx, "only the 3 section separators are \\3")
	H.falsy(string.find(blob, "\n", 1, true), "no raw newline in the blob")
	H.truthy(string.find(blob, "s\tH\t", 1, true), "value sent as type H")
	local _, _, vblob = qs.deserialize_quest_data(blob)
	qs.deserialize_quest_vars(vblob)
	local got, found = H.saved(G, "s")
	H.truthy(found, "save_var called for s")
	H.eq(s, got, "string restored byte for byte")
end)

H.case("FX-QVARS-004 bad key and unencodable table are skipped, rest serialized", function()
	local m = H.marshal()
	local enc = m.encode
	m.encode = function(v)
		for _, x in pairs(v) do
			if type(x) == "function" then error("cannot encode function", 0) end
		end
		return enc(v)
	end
	local G, qs = setup(m)
	local ok, res = pcall(qs.serialize_quest_vars, { ["bad\tkey"] = 1, ok = 2, f = { fn = function() end } })
	H.truthy(ok, "no exception: " .. tostring(res))
	H.eq("ok\tn\t2", res, "only ok survives")
	H.log_has(G, "[XRRFIX] serialize: table f not encodable: ")
end)

H.case("FX-QVARS-005 corrupt M line logged, other lines still applied", function()
	local G, qs = setup()
	local ok, err = pcall(qs.deserialize_quest_vars, "x\tM\tZZ\ny\tn\t5")
	H.truthy(ok, "no exception: " .. tostring(err))
	H.log_has(G, "[XRRFIX] deserialize: table x failed: ")
	local y, found = H.saved(G, "y")
	H.truthy(found, "save_var(y) called")
	H.eq(5, y, "y")
	local _, xfound = H.saved(G, "x")
	H.falsy(xfound, "x not saved")
end)
