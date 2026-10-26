--!strict

local fs = require "@std/fs"
local process = require "@std/process"
local TemporaryDirectory = require "./temporary-directory"

export type Config = {
	root: string?,
	prefix: string?,
	command: { string },
	env: { [string]: string }?,
	requiredPaths: { string }?,
}

local function check(config: Config): { string }
	local requiredPaths: { string } = config.requiredPaths or {}
	local root = config.root or tostring(process.cwd())
	local head = process.run({ "git", "rev-parse", "HEAD" }, { cwd = root })
	if not head.ok then
		return { "clean-clone: cannot read HEAD: " .. head.stderr }
	end
	local status = process.run({ "git", "status", "--porcelain" }, { cwd = root })
	if not status.ok then
		return { "clean-clone: cannot inspect working tree: " .. status.stderr }
	end
	if string.match(status.stdout, "%S") ~= nil then
		return { "clean-clone: working tree is not clean: " .. status.stdout }
	end
	for _, path in requiredPaths do
		if not fs.exists(path) then
			return { "clean-clone: required path is absent: " .. path }
		end
	end
	return TemporaryDirectory.run(
		TemporaryDirectory.root(),
		config.prefix or "checks-clone",
		function(directory): { string }
			local cloned = process.run { "git", "clone", "--quiet", "--no-local", root, directory }
			if not cloned.ok then
				return { "clean-clone: clone failed: " .. cloned.stderr }
			end
			local checkout =
				process.run { "git", "-C", directory, "checkout", "--quiet", (string.gsub(head.stdout, "%s+$", "")) }
			if not checkout.ok then
				return { "clean-clone: checkout failed: " .. checkout.stderr }
			end
			local environment: { [string]: string } = {}
			for name, value in process.env do
				environment[name] = value
			end
			local overrides: { [string]: string } = config.env or {}
			for name, value in overrides do
				environment[name] = value
			end
			local gate = process.run(config.command, { cwd = directory, env = environment })
			if not gate.ok then
				return { "clean-clone: gate failed:\n" .. gate.stdout .. gate.stderr }
			end
			return {}
		end
	)
end

return check
