--!strict

local Verify = require "../core"
local Binding = require "./binding"
local Wire = require "./wire"

type Report = Verify.Report

export type Verdict = {
	report: Report?,
	kind: "accepted" | "malformed" | "stale" | "foreign" | "invalid",
	detail: string,
}

local RECEIPT_VERSION = 1

local function encode(json: Binding.Json, runId: string, batchId: string, report: Report): string
	return json.encode {
		receiptVersion = RECEIPT_VERSION,
		runId = runId,
		batchId = batchId,
		report = report,
	}
end

local function check(json: Binding.Json, encoded: string, runId: string, batchId: string): Verdict
	local parsed, value: unknown = pcall(json.decode, encoded)
	if not parsed then
		return { kind = "malformed", detail = "the receipt is not parseable: " .. tostring(value) }
	end
	if type(value) ~= "table" then
		return { kind = "malformed", detail = "the receipt is not an object" }
	end
	local raw = Wire.normalize(value) :: { [string]: unknown }
	if raw.receiptVersion ~= RECEIPT_VERSION then
		return {
			kind = "malformed",
			detail = ("the receipt version %s is not %d"):format(tostring(raw.receiptVersion), RECEIPT_VERSION),
		}
	end
	if raw.runId ~= runId then
		return { kind = "stale", detail = ("the receipt belongs to run %s, not %s"):format(tostring(raw.runId), runId) }
	end
	if raw.batchId ~= batchId then
		return {
			kind = "foreign",
			detail = ("the receipt belongs to batch %s, not %s"):format(tostring(raw.batchId), batchId),
		}
	end
	local decoded, report: unknown = pcall(Verify.decode, raw.report)
	if not decoded then
		return { kind = "invalid", detail = "the receipt report is invalid: " .. tostring(report) }
	end
	return { kind = "accepted", report = report :: Report, detail = "accepted" }
end

return {
	RECEIPT_VERSION = RECEIPT_VERSION,
	encode = encode,
	check = check,
}
