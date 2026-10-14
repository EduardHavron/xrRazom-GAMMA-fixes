-- tests/lua/run.lua — unit tests for the FX-* fix scripts (specs/fixes/*.md).
-- Usage:  luajit tests/lua/run.lua [filter]      (filter = plain substring of case names)
--         python tests/lua/run_local.py [filter] (same, through lupa's embedded LuaJIT)
-- Exit code: 0 when no case failed (EXPECTED-FAIL cases do not count), 1 otherwise.

local script = (arg and arg[0]) or "tests/lua/run.lua"
local dir = string.match(script, "^(.*)[/\\][^/\\]*$") or "."

local H = dofile(dir .. "/harness.lua")
-- XRR_TEST_ROOT: alternative tree with mods/ (e.g. to check that a broken fix is caught)
H.root = (os.getenv and os.getenv("XRR_TEST_ROOT")) or (dir .. "/../..")

local files = {
	"test_qvars.lua",
	"test_tboard.lua",
	"test_turnin.lua",
	"test_fetch.lua",
	"test_laser.lua",
	"test_belt.lua",
	"test_parts.lua",
	"test_wsammo.lua",
	"test_killtr.lua",
	"test_lootclaim.lua",
}

for _, f in ipairs(files) do
	local chunk, err = loadfile(dir .. "/" .. f)
	if not chunk then
		print("FAIL  load " .. f .. ": " .. tostring(err))
		if XRR_TEST_NO_EXIT then return 1 end
		os.exit(1)
	end
	chunk(H)
end

local code = H.run_all(arg and arg[1])
if XRR_TEST_NO_EXIT then return code end
os.exit(code)
