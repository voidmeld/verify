--!strict

local fs = require "@std/fs"
local process = require "@std/process"
local Core = require "../core"
local Entry = require "../roblox/case-entry"
local Attachments = require "./attachments"
local Bounded = require "./bounded"
local Evidence = require "./evidence"
local OpenCloud = require "./open-cloud"
local Files = require "./files"
local Place = require "./place"
local ProgressFile = require "./progress-file"
local Player = require "./player"
local Published = require "./published-source"
local Studio = require "./studio"
local Attach = require "./studio-attach"
local Wire = require "./wire"

type Attachments_Limits = Core.AttachmentLimits

export type Options = {
	host: Entry.Host,
	entry: string,
	caseIds: { string }?,
	roots: { string }?,
	frameworkDirectory: string?,
	output: string?,
	deadlineSeconds: number?,
	place: string?,
	basePlace: string?,
	onProgress: ((Core.ProgressEvent) -> ())?,
	progressFile: string?,
	attach: Attach.Options?,
	cloud: OpenCloud.Options?,
	placeId: number?,
	clientEntry: string?,
	serverEntry: string?,
	players: number?,
	context: ("Server" | "Client")?,
	finalCapture: boolean?,
	attachments: Attachments_Limits?,
	attachmentSink: Attachments.Sink?,
	requiredMedia: { string }?,
	requiredEvidence: { Evidence.Requirement }?,
}
export type Result = {
	report: Core.Report,
	directory: string,
	reportPath: string,
	cloud: OpenCloud.Outcome?,
}

local function absolute(path: string): string
	return if path:sub(1, 1) == "/" then path else tostring(process.cwd()) .. "/" .. path
end

local function literalIds(ids: { string }?): string
	if ids == nil then
		return "nil"
	end
	local values: { string } = {}
	for _, id in ids do
		table.insert(values, string.format("%q", id))
	end
	return "{" .. table.concat(values, ",") .. "}"
end

local function engineCode(framework: string, entry: string, ids: { string }?, host: string?, progress: boolean?): string
	return "local Entry = require("
		.. Place.moduleExpression(framework .. "/src/roblox/case-entry.luau")
		.. ")\n"
		.. "local Channel = require("
		.. Place.moduleExpression(framework .. "/src/roblox/report-channel.luau")
		.. ")\n"
		.. "local factory = require("
		.. Place.moduleExpression(entry)
		.. ")\n"
		.. (if progress == true
			then "local Progress = require("
				.. Place.moduleExpression(framework .. "/src/roblox/progress-channel.luau")
				.. ")\n"
				.. "local http = game:GetService('HttpService')\n"
				.. "local progress = Progress.publisher(runId, progressToken, function(value) return http:JSONEncode(value) end, print)\n"
			else "local progress = nil\n")
		.. "local report = Entry.run(factory, '"
		.. (host or "studio")
		.. "', "
		.. literalIds(ids)
		.. ", progress, runId)\n"
		.. "return game:GetService('HttpService'):JSONEncode(Channel.envelope(runId, report))"
end

local function failure(options: Options, status: "failed" | "timed_out", message: string): Core.Report
	return Core.syntheticReport {
		executor = "verify-run",
		environment = { host = options.host :: string, entry = options.entry },
		id = "verify:execution",
		name = "host execution",
		status = status,
		message = message,
	}
end

local function appendFailure(report: Core.Report, options: Options, name: string, message: string): Core.Report
	local present: { [string]: boolean } = {}
	for _, result in report.results do
		present[result.id] = true
	end
	local id = "verify:" .. name
	while present[id] do
		id ..= ":failure"
	end
	local failed = failure(options, "failed", message)
	failed.results[1].id = id
	return Core.merge({ report, failed }, "verify-run", { host = options.host :: string, entry = options.entry })
end

local function run(options: Options): Result
	local directory = Files.claimDirectory(absolute(options.output or ".verify"))
	local framework = options.frameworkDirectory or "."
	local seconds = options.deadlineSeconds or 90
	local outcome: Core.BatchOutcome
	local cloud: OpenCloud.Outcome? = nil
	local progressPath: string? = nil
	local ok, thrown = pcall(function()
		assert(seconds > 0 and seconds < math.huge, "deadline must be finite and positive")
		assert(options.entry ~= "", "entry module is required")
		assert(
			options.host == "simulator"
				or options.host == "studio"
				or options.host == "player"
				or options.host == "open-cloud",
			"unknown host"
		)
		if options.caseIds ~= nil then
			assert(#options.caseIds > 0, "case selection is empty")
			local seen: { [string]: boolean } = {}
			for _, id in options.caseIds do
				assert(id ~= "" and not seen[id], "empty or duplicate selected case")
				seen[id] = true
			end
		end
		progressPath = options.progressFile
		if progressPath == nil and options.onProgress ~= nil then
			progressPath = directory .. "/progress.jsonl"
		end
		if progressPath ~= nil then
			assert(options.host == "simulator" or options.host == "studio", "this host does not report progress")
			Files.removeIfPresent(progressPath)
			Files.removeIfPresent(progressPath .. ".diagnostics")
		end
		if options.host == "simulator" then
			local command = {
				"lute",
				"run",
				framework .. "/tools/run-worker.luau",
				absolute(options.entry),
				directory .. "/worker-report",
			}
			for _, id in options.caseIds or ({} :: { string }) do
				table.insert(command, id)
			end
			if progressPath ~= nil then
				table.insert(command, 1, "VERIFY_PROGRESS_RUN=" .. directory)
				table.insert(command, 1, "VERIFY_PROGRESS_FILE=" .. absolute(progressPath))
				table.insert(command, 1, "/usr/bin/env")
			end
			local result = Bounded.run(command, seconds)
			fs.writeStringToFile(directory .. "/host.log", result.stdout .. result.stderr)
			if result.timedOut then
				outcome = { status = "timed_out", detail = "simulator process exceeded deadline" }
			elseif not result.ok then
				outcome = { status = "faulted", detail = result.stderr .. result.stdout }
			else
				outcome =
					{ status = "returned", report = Wire.decode(fs.readFileToString(directory .. "/worker-report")) }
			end
			Files.removeIfPresent(directory .. "/worker-report")
		elseif options.host == "studio" then
			assert(options.basePlace == nil or options.place == nil, "choose place or basePlace, not both")
			assert(options.basePlace == nil or options.attach == nil, "an attached Studio has no base place to merge")
			local place = options.place or directory .. "/fixture.rbxlx"
			if options.place == nil and options.attach == nil then
				local roots = { framework .. "/src/core", framework .. "/src/roblox" }
				for _, root in options.roots or ({} :: { string }) do
					table.insert(roots, root)
				end
				local modules = { options.entry }
				local function bootstrap(entry: string?): string?
					if entry == nil then
						return nil
					end
					table.insert(modules, entry)
					return "require(" .. Place.moduleExpression(entry) .. ")()"
				end
				local clientSource = bootstrap(options.clientEntry)
				local serverSource = bootstrap(options.serverEntry)
				Place.build {
					output = place,
					basePlace = options.basePlace,
					roots = roots,
					modules = modules,
					clientSource = clientSource,
					serverSource = serverSource,
				}
			end
			outcome = Studio.run {
				attach = options.attach,
				place = place,
				code = engineCode(framework, options.entry, options.caseIds, nil, progressPath ~= nil),
				worker = framework .. "/tools/studio-worker.luau",
				deadlineSeconds = seconds,
				directory = directory .. "/studio",
				players = options.players,
				context = options.context,
				finalCapture = options.finalCapture,
				progressFile = if progressPath ~= nil then absolute(progressPath) else nil,
			}
		elseif options.host == "open-cloud" then
			assert(options.cloud ~= nil, "open-cloud requires a connection with caller-supplied request and authorize")
			assert(options.players == nil, "open-cloud runs have no joined clients")
			local settings = table.clone(options.cloud)
			if options.deadlineSeconds ~= nil then
				settings.pollSeconds = options.deadlineSeconds
			end
			local session = OpenCloud.connect(settings)
			cloud = session.run {
				code = engineCode(framework, options.entry, options.caseIds, "open-cloud"),
				runId = directory,
				requires = nil,
			}
			local finished = cloud :: OpenCloud.Outcome
			outcome = if finished.status == "returned"
				then { status = "returned", report = finished.report }
				else {
					status = if finished.status == "timed_out" then "timed_out" else "faulted",
					detail = OpenCloud.describe(finished),
				}
		else
			outcome = Player.run {
				placeId = assert(options.placeId, "Player requires --place-id"),
				runId = directory,
				logPath = directory .. "/host.log",
				entry = options.entry,
				caseIds = options.caseIds,
				deadlineSeconds = seconds,
			}
		end
	end)
	local diagnostics: string? = nil
	if progressPath ~= nil and fs.exists(progressPath .. ".diagnostics") then
		local read, found = pcall(function()
			return Wire.parse(fs.readFileToString(progressPath .. ".diagnostics"))
		end)
		if read and type(found) == "table" then
			local record = found :: { [string]: unknown }
			diagnostics = ("progress was degraded: %s frame(s) rejected, %s poll failure(s); %s"):format(
				tostring(record.rejected),
				tostring(record.failures),
				tostring(record.first)
			)
		end
	end
	if progressPath ~= nil and options.onProgress ~= nil then
		for _, event in ProgressFile.read(progressPath, directory) do
			pcall(options.onProgress, event)
		end
	end
	local report: Core.Report
	if not ok then
		report = failure(options, "failed", tostring(thrown))
	else
		local completed = outcome :: Core.BatchOutcome
		if completed.status == "returned" then
			local decoded, value = pcall(Core.decode, completed.report)
			if decoded then
				report = value :: Core.Report
				if report.total == 0 then
					report = failure(options, "failed", "host returned an empty report")
				elseif options.caseIds ~= nil then
					local actual: { [string]: boolean } = {}
					for _, result in report.results do
						actual[result.id] = true
					end
					local matches = report.total == #options.caseIds
					for _, id in options.caseIds do
						matches = matches and actual[id] == true
					end
					if not matches then
						report =
							appendFailure(report, options, "selection", "host report does not match selected case ids")
					end
				end
			else
				report = failure(options, "failed", tostring(value))
			end
		else
			report = failure(
				options,
				if completed.status == "timed_out" then "timed_out" else "failed",
				completed.detail or "host failed"
			)
		end
	end
	if ok then
		local carried = false
		for _, result in report.results do
			for _, artifact in result.artifacts do
				carried = carried or artifact.content ~= nil
			end
		end
		if carried then
			local delivered, issues = Attachments.materialize(report, {
				directory = directory,
				sink = options.attachmentSink,
				limits = options.attachments,
				supported = options.host == "simulator" or options.host == "studio",
				host = options.host,
			})
			report = delivered
			if #issues > 0 then
				report = appendFailure(report, options, "attachments", table.concat(issues, "\n"))
			end
		end
	end
	if diagnostics ~= nil and report.results[1] ~= nil then
		table.insert(report.results[1].limitations, diagnostics)
	end
	local required: { Evidence.Requirement } = table.clone(options.requiredEvidence or {})
	for _, case in report.results do
		for _, mediaType in options.requiredMedia or ({} :: { string }) do
			table.insert(required, { caseId = case.id, mediaType = mediaType })
		end
	end
	local evidence = Evidence.write(report, directory, required)
	if #evidence.issues > 0 then
		report = appendFailure(evidence.report, options, "evidence", table.concat(evidence.issues, "\n"))
		Evidence.finish(report, directory)
	else
		report = evidence.report
	end
	return { report = report, directory = directory, reportPath = evidence.reportPath, cloud = cloud }
end

return { run = run, buildPublished = Published.build }
