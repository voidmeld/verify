--!strict

local Seal = require "@self/seal"
local Validation = require "@self/validation"

export type Subject = Seal.Subject
export type Issue = Validation.Issue
export type ExpectedBuild = Validation.Expected
export type Requirement = Validation.Requirement
export type Cell = Validation.Cell
export type Attestation = Validation.Attestation
export type Policy = Validation.Policy
export type Result = Validation.Result
export type SealOptions = Seal.SealOptions
export type SealIssue = Seal.Issue
export type Sealed = Seal.Sealed
export type ReviewBinding = Seal.ReviewBinding

return {
	seal = Seal.seal,
	bindReview = Seal.bindReview,
	validate = Validation.validate,
	explain = Validation.explain,
	expand = Validation.expand,
}
