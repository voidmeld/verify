--!strict

local Fake = require "@self/fake"

export type Options = Fake.Options
export type Fault = Fake.Fault
export type UnitRun = Fake.UnitRun
export type FakeHost = Fake.FakeHost

return {
	fake = Fake.create,
	FAKE_CAPABILITIES = Fake.DEFAULT_CAPABILITIES,
}
