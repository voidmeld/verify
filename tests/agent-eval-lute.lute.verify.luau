--!strict

local AgentEval = require "../src/agent-eval"
local Verify = require "../src/core"

local binding = AgentEval.lute
local ROOT = binding.absolute ".lute/tmp/agent-eval-lute"

local AGENT = [[
local io = require("@lute/io")
local process = require("@std/process")
local task = require("@std/task")
local ok, input = pcall(io.read)
local echoed = if ok then string.gsub(input, "%s+$", "") else ""
print('{"type":"system","subtype":"init","echo":"' .. echoed .. '"}')
task.wait(0.4)
print('{"type":"result","subtype":"success"}')
process.exit(3)
]]

local SHELL_AGENT = [[read line; echo "{\"echo\":\"$line\"}"; sleep 0.4; echo '{"type":"result"}'; exit 3]]

local SLEEPER = [[
local task = require("@std/task")
task.wait(30)
print("late")
]]

local function prepare(): string
	local files = binding.files
	if files.exists(ROOT) then
		files.remove(ROOT)
	end
	files.makeDirectory(ROOT .. "/scratch")
	files.write(ROOT .. "/agent.luau", AGENT)
	files.write(ROOT .. "/sleeper.luau", SLEEPER)
	files.write(ROOT .. "/prompt.md", "hello")
	return ROOT
end

return function(suite: Verify.Harness)
	suite:suite("agent evaluation Lute binding", function()
		suite:case("stamps each output line, feeds the prompt file and keeps the exit code", function(context)
			local root = prepare()
			local services = binding.services { workspaces = root .. "/live" }
			local execution = services.execute {
				argv = { "sh", "-c", SHELL_AGENT },
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
			local first = execution.lines[1].at :: number
			local second = execution.lines[2].at :: number
			context:expect(second - first >= 0.3):toBe(true)
			context:expect(execution.seconds >= second):toBe(true)
		end)

		suite:case("captures plain output and stops a command at its deadline", function(context)
			local root = prepare()
			local services = binding.services { workspaces = root .. "/live" }
			local plain = services.execute {
				argv = { "lute", "run", root .. "/agent.luau" },
				cwd = root,
				input = nil,
				deadlineSeconds = 60,
				stamp = false,
				scratch = root .. "/scratch",
			}
			context:expect(plain.exitcode):toBe(3)
			context:expect(plain.lines[1].at):toBe(nil)
			context:expect(plain.lines[1].text):toBe '{"type":"system","subtype":"init","echo":""}'
			local late = services.execute {
				argv = { "lute", "run", root .. "/sleeper.luau" },
				cwd = root,
				input = nil,
				deadlineSeconds = 1,
				stamp = true,
				scratch = root .. "/scratch",
			}
			context:expect(late.timedOut):toBe(true)
			context:expect(#late.lines):toBe(0)
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
