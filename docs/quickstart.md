# Quickstart

This guide runs one case on Lute and prints its report. It needs no Roblox host.

## Install Verify

1. Install [Rokit](https://github.com/rojo-rbx/rokit).
2. Clone `https://github.com/voidmeld/verify.git` into your application's checkout.
3. Check out one exact Verify commit.
4. In the Verify directory, run `rokit install`.
5. Record `git rev-parse HEAD` and `git rev-parse HEAD^{tree}` in your application.

Keep the application and Verify under one Lute loading root.
Require the public `src/core` package from that copy.
The [consumer skill](../.agents/skills/verify/SKILL.md) describes adoption beyond this first case.

## Run a passing case

In the Verify directory, run:

```sh
lute run examples/quickstart.luau
```

The [complete example](../examples/quickstart.luau) creates a harness, registers a case and prints a report.
Its essential calls are:

```luau
local Core = require "../src/core"
local harness = Core.createHarness { now = os.clock }

harness:case("adds numbers", function(context)
    context:expect(2 + 2):toBe(4)
end)

local report = harness:run {
    executor = "quickstart",
    capabilities = {},
    environment = { revision = "working-tree" },
}
print(Core.format(report))
```

The relative import above assumes a file in Verify's `examples` directory.
For an application file, change only the import to reach your pinned copy's `src/core`.
Run Lute from the common loading root.

`now` supplies the clock. The callback receives the case context.
The context records assertions and releases case resources.
`harness:run` returns a report. It does not set the process exit code.

## Read the report and test failure

The report must have `total == 1` and `passed == 1`.
Its result row must have `status == "passed"`.
The complete example exits with code 1 if `report.passed ~= report.total`.
Use that check in a command that must fail when a case does not pass.
Also reject an empty report when your command permits selection.

1. Copy the complete example to another file in the same directory.
2. Change `toBe(4)` to `toBe(5)` in the copy.
3. Run the copy with `lute run`.
4. Check that the report contains one failed case and the command exits with code 1.
5. Change the expected value back to 4.
6. Run the copy again and check that it passes.
7. Remove the copy.

An unsupported capability, a skip or a timeout does not pass.
This first run checks arithmetic on Lute. It proves no engine or media behavior.

## Continue

- Use [cases and sessions](api.md#cases-and-sessions) for registration and cleanup.
- Use [assertions and spies](api.md#assertions-and-spies) to compare values and inspect calls.
- Use the [run guide](running.md) for named case collections and saved reports on other hosts.
- Use [CONTRIBUTING.md](../CONTRIBUTING.md) to change Verify itself.
