--!strict

local Gate = require "../gate"

export type Entry = { name: string, kind: "file" | "directory" }

export type Files = {
	read: (path: string) -> string,
	write: (path: string, contents: string) -> (),
	exists: (path: string) -> boolean,
	isDirectory: (path: string) -> boolean,
	list: (path: string) -> { Entry },
	makeDirectory: (path: string) -> (),
	remove: (path: string) -> (),
	copy: (from: string, to: string) -> (),
	move: (from: string, to: string) -> (),
}

export type Line = { at: number?, text: string }

export type Command = {
	argv: { string },
	cwd: string?,
	env: { [string]: string }?,
	input: string?,
	deadlineSeconds: number,
	stamp: boolean?,
	scratch: string?,
}

export type Execution = {
	started: boolean,
	exitcode: number,
	timedOut: boolean,
	unsupported: boolean?,
	stdout: string,
	stderr: string,
	lines: { Line },
	seconds: number,
	detail: string?,
}

export type HttpRequest = {
	url: string,
	method: string,
	headers: { [string]: string },
	body: string?,
	deadlineSeconds: number,
}

export type HttpResponse = { status: number, body: string }

export type Services = {
	files: Files,
	execute: (command: Command) -> Execution,
	checks: (gate: Gate.Definition, directory: string, runId: string) -> Gate.Outcome,
	hash: (bytes: string) -> string,
	now: () -> number,
	clock: () -> number,
	spawn: (body: () -> ()) -> (),
	wait: (seconds: number) -> (),
	request: ((request: HttpRequest) -> (HttpResponse?, string?))?,
	environment: (name: string) -> string?,
	print: (line: string) -> (),
	workspaces: string,
}

local function lines(text: string): { Line }
	local result: { Line } = {}
	for line in string.gmatch(text, "[^\r\n]+") do
		table.insert(result, { at = nil, text = line })
	end
	return result
end

return {
	lines = lines,
}
