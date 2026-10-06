--!strict

local fs = require "@std/fs"
local process = require "@std/process"
local Core = require "../core"
local Files = require "./files"
local Wire = require "./wire"

export type Requirement = { caseId: string, actor: string?, checkpoint: string?, mediaType: string }
export type Result = { report: Core.Report, issues: { string }, reportPath: string }
type Captured = { caseId: string, actor: string?, checkpoint: string?, mediaType: string? }

local function absolute(value: string): string
	return if string.sub(value, 1, 1) == "/" then value else tostring(process.cwd()) .. "/" .. value
end

local function safe(value: string): string
	local normalized = string.gsub(value, "[^%w._-]", "_")
	return string.sub(normalized, 1, 60)
end

local function write(report: Core.Report, directory: string, required: { Requirement }?): Result
	assert(directory ~= "", "evidence directory must not be empty")
	local requirements: { Requirement } = required or {}
	for _, requirement in requirements do
		assert(
			requirement.caseId ~= "" and requirement.mediaType ~= "",
			"evidence requirements need a case and media type"
		)
		assert(requirement.actor == nil or requirement.actor ~= "", "evidence actor must not be empty")
		assert(requirement.checkpoint == nil or requirement.checkpoint ~= "", "evidence checkpoint must not be empty")
	end
	local copy = Wire.decode(Wire.encode(report))
	local destination = absolute(directory)
	Files.ensureDirectory(destination)
	local artifactsDirectory: string? = nil
	local captured: { Captured } = {}
	local summary = { Core.format(copy), "", "Artifacts:" }
	local count = 0
	local function persist(artifact: Core.Artifact, caseId: string, actor: string?, checkpoint: string?)
		count += 1
		local identity = caseId
			.. (if actor then " / " .. actor else "")
			.. (if checkpoint then " / " .. checkpoint else "")
			.. " / "
			.. artifact.name
		local reference = artifact.reference
		local ok, reason = pcall(function()
			assert(reference ~= "" and not string.match(reference, "^%a[%w+.-]*:"), "reference is not a local file")
			local source = absolute(reference)
			local metadata = fs.metadata(source)
			assert(metadata.type == "file" and metadata.size > 0, "local reference must be a nonempty regular file")
			local bytes = fs.readFileToString(source)
			assert(#bytes > 0, "artifact became empty while reading")
			if artifactsDirectory == nil then
				artifactsDirectory = Files.claimDirectory(destination .. "/artifacts")
			end
			local suffix = string.match(source, "(%.[%w]+)$") or ""
			local filename = string.format("%04d-%s%s", count, safe(artifact.name), suffix)
			local output = (artifactsDirectory :: string) .. "/" .. filename
			fs.writeStringToFile(output, bytes)
			assert(fs.metadata(output).size == #bytes, "artifact copy is incomplete")
			artifact.reference = output
		end)
		if ok then
			table.insert(
				captured,
				{ caseId = caseId, actor = actor, checkpoint = checkpoint, mediaType = artifact.mediaType }
			)
			table.insert(summary, "saved " .. identity .. ": " .. artifact.reference)
		else
			table.insert(summary, "MISSING " .. identity .. ": " .. reference .. " (" .. tostring(reason) .. ")")
		end
	end
	for _, result in copy.results do
		for _, artifact in result.artifacts do
			persist(artifact, result.id, nil, nil)
		end
		if result.evidence then
			for _, checkpoint in result.evidence.checkpoints do
				for _, artifact in checkpoint.artifacts do
					persist(artifact, result.id, checkpoint.actor, checkpoint.name)
				end
			end
		end
	end
	if count == 0 then
		table.insert(summary, "none")
	end
	local issues: { string } = {}
	for _, requirement in requirements do
		local found = false
		for _, item in captured do
			if
				item.caseId == requirement.caseId
				and item.mediaType == requirement.mediaType
				and (requirement.actor == nil or item.actor == requirement.actor)
				and (requirement.checkpoint == nil or item.checkpoint == requirement.checkpoint)
			then
				found = true
				break
			end
		end
		if not found then
			local issue = "required durable evidence missing: "
				.. requirement.caseId
				.. " / "
				.. (requirement.actor or "any actor")
				.. " / "
				.. (requirement.checkpoint or "any checkpoint")
				.. " / "
				.. requirement.mediaType
			table.insert(issues, issue)
			table.insert(summary, "MISSING " .. issue)
		end
	end
	local reportPath = destination .. "/report.json"
	fs.writeStringToFile(reportPath, Wire.encode(copy))
	fs.writeStringToFile(destination .. "/summary.txt", table.concat(summary, "\n") .. "\n")
	return { report = copy, issues = issues, reportPath = reportPath }
end

local function finish(report: Core.Report, directory: string): string
	local destination = absolute(directory)
	local summaryPath = destination .. "/summary.txt"
	local previous = fs.readFileToString(summaryPath)
	local index = string.find(previous, "\nArtifacts:", 1, true)
	assert(index ~= nil, "evidence summary is missing its artifact section")
	local reportPath = destination .. "/report.json"
	fs.writeStringToFile(reportPath, Wire.encode(report))
	fs.writeStringToFile(summaryPath, Core.format(report) .. "\n" .. string.sub(previous, index :: number))
	return reportPath
end

return { write = write, finish = finish }
