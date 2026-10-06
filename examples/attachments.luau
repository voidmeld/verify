--!strict

local fs = require "@std/fs"
local Files = require "../src/lute/files"
local Platform = require "../src/lute/platform"

local root = Files.claimDirectory "/tmp/verify-attachments-example"
local result = Platform.run {
	host = "simulator",
	entry = "examples/attachments-entry.luau",
	caseIds = { "attach-ok" },
	output = root,
	deadlineSeconds = 20,
}
local artifact = result.report.results[1].artifacts[1]
print(
	("attachments: %s %d bytes sha256 %s"):format(
		artifact.name,
		artifact.size or 0,
		string.sub(artifact.sha256 or "", 1, 12)
	)
)
assert(fs.readFileToString(artifact.reference) == "line one\nline two\n", "attachment bytes differ")
fs.removeDirectory(root, { recursive = true })
