--[[
	Unit test runner for the Roblox-independent game logic (src/shared).

	Runs on the PC with Lune:   lune run tests/run
	Optional filter:            lune run tests/run -- Board

	The shared modules use Rojo-style requires (require(script.Parent.X)).
	This runner emulates `script` with lightweight path references so the exact
	same source files run here and in Roblox.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local stdio = require("@lune/stdio")

local moduleCache = {}
local refMeta = {}

local function makeRef(path: string)
	return setmetatable({ __path = path }, refMeta)
end

refMeta.__index = function(self, key)
	local path = rawget(self, "__path")
	if key == "Parent" then
		return makeRef(string.match(path, "^(.*)/[^/]+$") or "")
	end
	return makeRef(path .. "/" .. key)
end
refMeta.__tostring = function(self)
	return "ScriptRef(" .. rawget(self, "__path") .. ")"
end

local loadFile

local function customRequire(target)
	if type(target) == "string" then
		return require(target)
	end
	local path = rawget(target, "__path")
	assert(path, "require() expects a script reference")
	if moduleCache[path] ~= nil then
		return moduleCache[path]
	end
	local file
	if fs.isFile(path .. ".luau") then
		file = path .. ".luau"
	elseif fs.isFile(path .. "/init.luau") then
		file = path .. "/init.luau"
	else
		error("module not found: " .. path)
	end
	local result = loadFile(file, makeRef(path))
	moduleCache[path] = result
	return result
end

function loadFile(file: string, scriptRef, extraEnv)
	local source = fs.readFile(file)
	local env = { script = scriptRef, require = customRequire }
	for k, v in extraEnv or {} do
		env[k] = v
	end
	local chunk = luau.load(source, { debugName = file, environment = env })
	return chunk()
end

-- Minimal test framework -----------------------------------------------------
local results = { passed = 0, failed = 0, failures = {} }
local filter = process.args[1]

local function test(name: string, fn)
	if filter and not string.find(name, filter, 1, true) then
		return
	end
	local ok, err = xpcall(fn, debug.traceback)
	if ok then
		results.passed += 1
		print(stdio.color("green") .. "  ✓ " .. stdio.color("reset") .. name)
	else
		results.failed += 1
		table.insert(results.failures, { name = name, err = err })
		print(stdio.color("red") .. "  ✗ " .. name .. stdio.color("reset"))
	end
end

local function fmt(v)
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end

local expect = {}
function expect.eq(actual, expected, msg)
	if actual ~= expected then
		error(string.format("%sexpected %s, got %s", msg and (msg .. ": ") or "", fmt(expected), fmt(actual)), 2)
	end
end
function expect.truthy(v, msg)
	if not v then
		error((msg or "expected truthy value") .. ", got " .. fmt(v), 2)
	end
end
function expect.falsy(v, msg)
	if v then
		error((msg or "expected falsy value") .. ", got " .. fmt(v), 2)
	end
end
function expect.ok(ok, err, msg)
	if not ok then
		error((msg and (msg .. ": ") or "") .. "expected success, got error " .. fmt(err), 2)
	end
end
function expect.fails(ok, err, pattern)
	if ok then
		error("expected failure" .. (pattern and (" matching " .. pattern) or ""), 2)
	end
	if pattern and not string.find(tostring(err), pattern, 1, true) then
		error(string.format("expected error containing %q, got %s", pattern, fmt(err)), 2)
	end
end

-- Run every tests/*.spec.luau -------------------------------------------------
local specs = {}
for _, name in fs.readDir("tests") do
	if string.match(name, "%.spec%.luau$") then
		table.insert(specs, name)
	end
end
table.sort(specs)

local env = { Shared = makeRef("src/shared"), test = test, expect = expect }
for _, name in specs do
	print(stdio.style("bold") .. name .. stdio.style("reset"))
	moduleCache = {}
	local ok, err = pcall(loadFile, "tests/" .. name, makeRef("tests/" .. name), env)
	if not ok then
		results.failed += 1
		table.insert(results.failures, { name = name .. " (load)", err = err })
		print(stdio.color("red") .. "  ✗ failed to load: " .. tostring(err) .. stdio.color("reset"))
	end
end

print("")
for _, f in results.failures do
	print(stdio.color("red") .. "FAIL " .. f.name .. stdio.color("reset"))
	print(f.err)
end
print(string.format("%d passed, %d failed", results.passed, results.failed))
process.exit(results.failed == 0 and 0 or 1)
