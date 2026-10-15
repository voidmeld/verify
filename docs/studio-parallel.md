# Studio concurrency investigation

Investigation on 2026-10-15, based on `ff2a119`, without launching Studio.
Live concurrent Studio execution remains unvalidated.

## Observations

Verify starts one MCP child per run. On Windows a hidden PowerShell bridge redirects the child's stdin, stdout and stderr. It forwards numbered request files to stdin, copies stdout to `mcp/output` and stderr to `mcp/errors`, and writes the child's exit code to `mcp/exited` after it exits. Closing a connection asks the bridge to kill its own child's process tree. The outer watchdog also owns only its worker tree.

The installed `StudioMCP.exe` in `version-4f087c32742644ab` contains a WebSocket host election and proxy clients. Its diagnostic strings distinguish binding the host port, connecting to an existing host, reconnecting and re-binding. A shared transport exists, but that does not establish that one proxy exiting terminates its siblings.

A read-only probe started three MCP clients with redirected streams, initialized each, and called `list_roblox_studios`. All three returned the same `{ studios: [{ id, name }] }` listing for the one already-open Studio. Killing the first probe child left both other children alive; both answered a second listing. The probe never launched Studio, toggled play or executed engine code. This refutes unconditional sibling-exit propagation for proxy clients. It does not test loss of the elected WebSocket host, or listings with several Studios open.

Historical temporary run directories `verify-studio/run-1792070634-13` through `run-1792073343-24` include exit files containing `1` and empty error files. These records cannot distinguish a natural failure from Verify's own forced cleanup. Two older initialization logs from another Verify checkout record stdin access denied and connection closed during initialization. Neither establishes the cause of the reported overlapping-run failures. Failing-run diagnostics are still needed to confirm that trigger.

The code does establish two Verify failure boundaries:

- The launched worker used one MCP connection for its entire lifetime and aborted on its exit. The attach transport retried only requests known to be unsent. The detached start cleared its receipt and spawned again, so blindly replaying a lost start reply could repeat the case.
- Cleanup selected any new Studio process carrying `-task StartServer` or `-rbxTransportToken`, even when it belonged to another concurrent run. Snapshots exclude processes already open, but do not establish ownership of processes started afterward.

Discovery uses the new document's unique name and ID. Later tool calls carry that exact ID. The engine run token, detached receipt prefix and report envelope bind results to the run. These prevent selecting another run's result; they neither keep an MCP process alive nor establish ownership of another process. Multi-Studio listing and ID stability through host failover still need live validation.

## Chosen boundary

Verify keeps per-run MCP children and recovers bounded transport loss rather than introducing a machine daemon and lease protocol. See [native Studio execution](execution.md#native-studio-execution) for the retry contract. This repairs the confirmed missing lifetime boundary without assuming the unconfirmed shared-host failure mechanism. It does not claim that every possible StudioMCP exit can be recovered.

Fake tests exercise healthy lifetime, bounded reconnection, unchanged target bytes, failed reopen, deadlines, uncertain mutation delivery, shutdown and receipt-preserving recovery. Process tests exercise two concurrent ownership trees. They prove no engine or native concurrency claim.

## Deferred validation commands

Run these only when Studio is available. Open PowerShell in `C:\git\verify-wt\parallel` and paste the following function. It starts the requested number of independent runs at once, waits for their reports, and checks exit codes and case counts. With `-KillMcp`, it waits for run 1 to report a running detached receipt and kills only that run's recorded MCP PID. It leaves every evidence directory available for inspection.

```powershell
$env:PATH = "$env:USERPROFILE\.rokit\tool-storage\luau-lang\lute\1.0.1-nightly.20261006;$env:USERPROFILE\.rokit\tool-storage\johnnymorganz\luau-lsp\1.69.0;$env:USERPROFILE\.rokit\tool-storage\johnnymorganz\stylua\2.5.2;$env:USERPROFILE\.rokit\tool-storage\rojo-rbx\rojo\7.7.0;C:\Program Files\Git\usr\bin;$env:PATH"
Set-Location C:\git\verify-wt\parallel

function Test-VerifyStudioParallel {
    param([ValidateSet(2, 3)][int]$Count, [switch]$KillMcp)
    $ErrorActionPreference = 'Stop'
    $batch = Join-Path $PWD ('.verify\parallel-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $batch | Out-Null
    $runs = @()
    foreach ($n in 1..$Count) {
        $destination = Join-Path $batch "run-$n"
        $arguments = @('run', 'tools/run.luau', '--entry',
            'tests/programs/studio-parallel-entry.luau', '--host', 'studio',
            '--deadline', '180', '--output', $destination)
        $child = Start-Process -FilePath (Get-Command lute).Source `
            -ArgumentList $arguments -WorkingDirectory $PWD -WindowStyle Hidden `
            -RedirectStandardOutput "$batch\$n.stdout" `
            -RedirectStandardError "$batch\$n.stderr" -PassThru
        $null = $child.Handle
        $runs += $child
    }
    if ($KillMcp) {
        $until = [DateTime]::UtcNow.AddSeconds(150)
        $running = $false
        while (-not $running -and [DateTime]::UtcNow -lt $until) {
            $outputs = Get-ChildItem "$batch\run-1" -Recurse -Filter output -ErrorAction SilentlyContinue
            foreach ($output in $outputs) {
                foreach ($line in Get-Content -LiteralPath $output.FullName) {
                    try {
                        $reply = $line | ConvertFrom-Json
                        foreach ($content in $reply.result.content) {
                            $state = $content.text | ConvertFrom-Json
                            if ($state.state -eq 'running') { $running = $true }
                        }
                    } catch { }
                }
            }
            if (-not $running) { Start-Sleep -Milliseconds 100 }
        }
        if (-not $running) { throw "No running receipt observed; inspect $batch" }
        $pidFile = Get-ChildItem "$batch\run-1" -Recurse -Filter pid |
            Where-Object { $_.Directory.Name -eq 'mcp' } | Select-Object -First 1
        if ($null -eq $pidFile) { throw "No owned MCP PID recorded; inspect $batch" }
        $mcpPid = [int](Get-Content -LiteralPath $pidFile.FullName -Raw)
        $mcp = Get-Process -Id $mcpPid
        if ($mcp.ProcessName -ne 'StudioMCP') { throw 'Recorded PID is not StudioMCP' }
        Stop-Process -Id $mcpPid -Force
        "Killed run 1 MCP PID $mcpPid"
    }
    foreach ($child in $runs) { $child.WaitForExit() }
    foreach ($n in 1..$Count) {
        $child = $runs[$n - 1]
        if ($child.ExitCode -ne 0) { throw "Run $n exited $($child.ExitCode); inspect $batch" }
        $reports = @(Get-ChildItem "$batch\run-$n" -Recurse -Filter report.json)
        if ($reports.Count -ne 1) { throw "Run $n returned $($reports.Count) reports" }
        $report = Get-Content -LiteralPath $reports[0].FullName -Raw | ConvertFrom-Json
        if ($report.total -ne 1 -or $report.passed -ne 1) { throw "Run $n did not pass exactly one case" }
    }
    if ($KillMcp) {
        $replacement = @(Get-ChildItem "$batch\run-1" -Recurse -Directory -Filter 'reconnect-*')
        if ($replacement.Count -eq 0) { throw 'No replacement MCP diagnostics found' }
    }
    "Passed $Count runs; evidence: $batch"
}

Test-VerifyStudioParallel -Count 2
Test-VerifyStudioParallel -Count 3
Test-VerifyStudioParallel -Count 3 -KillMcp
lute run tools/gate.luau --native
```

The held case checks its run token before and after a 30-second wait, and refuses a repeated case body. Success requires every run to pass exactly once, no wrong-run receipt, and replacement MCP diagnostics after the injected kill. Inspect `studio/mcp/output`, `errors`, `exited`, and any `reconnect-*` directories on failure. Also check that closing one run leaves the others' Studios alive. These commands test per-run child loss; testing an elected shared host's loss requires identifying its owner first and must not terminate another client's process without its authorization.
