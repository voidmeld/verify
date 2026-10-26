--!strict

local process = require "@std/process"
local AgentEval = require "../src/agent-eval"
local Files = require "../src/lute/files"
local Verify = require "../src/core"

local binding = AgentEval.lute
local ROOT = binding.absolute ".lute/tmp/agent-eval-lute"
local LUTE = binding.absolute(tostring(process.execPath()))

local AGENT = [[
local io = require("@lute/io")
local process = require("@std/process")
local task = require("@std/task")
local ok, input = pcall(io.read)
local echoed = if ok then string.gsub(input, "%s+$", "") else ""
io.write('{"echo":"' .. echoed .. '"}\n')
task.wait(0.4)
io.write('{"type":"result"}\n')
process.exit(3)
]]

local SLEEPER = [[
local task = require("@std/task")
task.wait(30)
print("late")
]]

local ECHO_ARGUMENTS = [[
local process = require("@std/process")
for index = 2, #process.args do
	print("<" .. process.args[index] .. ">")
end
]]

local OVERLAP = [[
local fs = require "@std/fs"
local process = require "@std/process"
local task = require "@std/task"
local root, workspace = process.args[2], process.args[3]
local arm = assert(string.match(workspace, "/([^/]+)/local/seed%-1$"))
local peer = if arm == "one" then "two" else "one"
fs.writeStringToFile(root .. "/" .. arm, "started")
local deadline = os.clock() + 5
while not fs.exists(root .. "/" .. peer) and os.clock() < deadline do
	task.wait(0.01)
end
assert(fs.exists(root .. "/" .. peer), "the other arm did not start before this arm ended")
print("overlapped")
]]

local function prepare(): string
	local files = binding.files
	if files.exists(ROOT) then
		files.remove(ROOT)
	end
	files.makeDirectory(ROOT .. "/scratch")
	files.write(ROOT .. "/agent.luau", AGENT)
	files.write(ROOT .. "/sleeper.luau", SLEEPER)
	files.write(ROOT .. "/arguments.luau", ECHO_ARGUMENTS)
	files.write(ROOT .. "/prompt.md", "hello")
	return ROOT
end

return function(suite: Verify.Harness)
	suite:suite("agent evaluation Lute binding", function()
		suite:case("starts both arms on fresh evidence and workspace trees before either child exits", function(context)
			local root = binding.absolute(Files.claimDirectory ".lute/tmp/agent-eval-overlap")
			local files = binding.files
			context:defer(function()
				files.remove(root)
			end)
			files.makeDirectory(root .. "/task/starter")
			files.makeDirectory(root .. "/barrier")
			files.write(root .. "/overlap.luau", OVERLAP)
			files.write(root .. "/task/brief.md", "Run the local overlap fixture.")
			files.write(
				root .. "/task/task.json",
				binding.encode {
					schemaVersion = 1,
					id = "task",
					title = "Local overlap",
					brief = "brief.md",
					starter = "starter",
					checks = {},
				}
			)
			local suitePath = root .. "/suite.json"
			files.write(
				suitePath,
				binding.encode {
					schemaVersion = 1,
					id = "overlap",
					tasks = { "task" },
					arms = { { id = "one" }, { id = "two" } },
					agents = { { id = "local", adapter = "local" } },
					seeds = { 1 },
					budgets = { wallSeconds = 15 },
					parallelism = 2,
				}
			)
			local configured = AgentEval.decodeSuite(binding.decode(files.read(suitePath)), suitePath, binding.loader())
			local summary = AgentEval.run {
				suite = configured,
				loader = binding.loader(),
				services = binding.services { workspaces = root .. "/workspaces" },
				adapters = {
					["local"] = AgentEval.adapters.command {
						id = "local",
						argv = { LUTE, "run", root .. "/overlap.luau", root .. "/barrier", "{workspace}" },
						stamp = true,
						decode = binding.decode,
					},
				},
				evidence = root .. "/evidence",
				encode = binding.encode,
				decode = binding.decode,
				resume = false,
			}
			context:expect(#summary.results):toBe(2)
			for _, result in summary.results do
				context:expect(result.status):toBe "completed"
				context:expect(result.passed):toBe(true)
				context:expect(result.session.result):toBe "overlapped"
				context:expect(files.exists(result.directory .. "/result.json")):toBe(true)
			end
		end)

		suite:case("stamps each output line, feeds the prompt file and keeps the exit code", function(context)
			local root = prepare()
			local services = binding.services { workspaces = root .. "/live" }
			local execution = services.execute {
				argv = { LUTE, "run", root .. "/agent.luau" },
				cwd = root,
				input = root .. "/prompt.md",
				deadlineSeconds = 60,
				stamp = true,
				scratch = root .. "/scratch",
			}
			context:expect(execution.started):toBe(true)
			context:expect(execution.timedOut):toBe(false)
			context:expect(execution.exitcode):toBe(3)
			context:expect(#execution.lines):toBe(2)
			context:expect(execution.lines[1].text):toBe '{"echo":"hello"}'
			context:expect(execution.lines[2].text):toBe '{"type":"result"}'
			local first = assert(execution.lines[1].at)
			local second = assert(execution.lines[2].at)
			context:expect(second - first >= 0.3):toBe(true)
			context:expect(execution.seconds >= second):toBe(true)
		end)

		suite:case("captures plain output and stops a command at its deadline", function(context)
			local root = prepare()
			local services = binding.services { workspaces = root .. "/live" }
			local plain = services.execute {
				argv = { LUTE, "run", root .. "/agent.luau" },
				cwd = root,
				deadlineSeconds = 60,
				stamp = false,
				scratch = root .. "/scratch",
			}
			context:expect(plain.exitcode):toBe(3)
			context:expect(plain.lines[1].at):toBe(nil)
			context:expect(plain.lines[1].text):toBe '{"echo":""}'
			local late = services.execute {
				argv = { LUTE, "run", root .. "/sleeper.luau" },
				cwd = root,
				deadlineSeconds = 1,
				stamp = true,
				scratch = root .. "/scratch",
			}
			context:expect(late.timedOut):toBe(true)
			context:expect(#late.lines):toBe(0)
		end)

		suite:case("passes arguments with spaces, quotes and backslashes unchanged", function(context)
			local root = prepare()
			local services = binding.services { workspaces = root .. "/live" }
			local words = { "plain", "two words", 'say "hi"', "trailing\\", 'back\\"quote', "", "tab\tand" }
			local argv = { LUTE, "run", root .. "/arguments.luau" }
			local expected: { string } = {}
			for _, word in words do
				table.insert(argv, word)
				table.insert(expected, "<" .. word .. ">")
			end
			local execution = services.execute {
				argv = argv,
				cwd = root,
				deadlineSeconds = 60,
				stamp = false,
				scratch = root .. "/scratch",
			}
			context:expect(execution.exitcode):toBe(0)
			local echoed: { string } = {}
			for _, line in execution.lines do
				table.insert(echoed, line.text)
			end
			context:expect(echoed):toEqual(expected)
		end)

		suite:case("copies, lists, moves and removes trees through the file binding", function(context)
			local root = prepare()
			local files = binding.files
			files.makeDirectory(root .. "/tree/a/b")
			files.write(root .. "/tree/a/b/c.txt", "c")
			files.write(root .. "/tree/top.txt", "t")
			local listed = files.list(root .. "/tree")
			table.sort(listed, function(left, right)
				return left.name < right.name
			end)
			context:expect(listed):toEqual {
				{ name = "a", kind = "directory" },
				{ name = "top.txt", kind = "file" },
			}
			files.copy(root .. "/tree/top.txt", root .. "/tree/a/copy.txt")
			context:expect(files.read(root .. "/tree/a/copy.txt")):toBe "t"
			files.move(root .. "/tree", root .. "/moved")
			context:expect(files.isDirectory(root .. "/moved/a/b")):toBe(true)
			context:expect(files.exists(root .. "/tree")):toBe(false)
			files.remove(root .. "/moved")
			context:expect(files.exists(root .. "/moved")):toBe(false)
			context:expect(binding.absolute "/x/./y/../z"):toBe "/x/z"
			context:expect(binding.absolute "C:\\a\\b"):toBe "C:/a/b"
			context:expect(string.sub(binding.STAMP, -10)):toBe "stamp.luau"
			context:expect(#binding.sha256 "abc"):toBe(64)
			context:expect(binding.sha256 "abc"):toBe "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
		end)
	end)
end
