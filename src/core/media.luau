--!strict

export type AudioWindow = { start: number?, span: number? }
export type ResolvedAudioWindow = { start: number, span: number }
export type AudioStream = { codec: string?, channels: number?, sampleRate: string? }
export type Recording = { duration: number, audio: AudioStream? }
export type ProbeStream = {
	codec_type: string,
	codec_name: string?,
	width: number?,
	height: number?,
	avg_frame_rate: string?,
	channels: number?,
	sample_rate: string?,
}
export type Probe = { format: { duration: (string | number)? }?, streams: { ProbeStream }? }
export type Summary = {
	duration: number,
	video: { width: number, height: number, codec: string?, frameRate: string? },
	audio: AudioStream?,
	audioSignal: "unmeasured" | "no_audio_stream",
	visualJudgment: "unproved",
	audioJudgment: "unproved",
}
export type AudioMeasurement = {
	maxVolumeDb: string?,
	meanVolumeDb: string?,
	silenceDetected: boolean,
	thresholdDb: number,
}
export type SampleCommand = {
	kind: "frame" | "audio",
	seconds: number,
	duration: number?,
	output: string,
	argv: { string },
}

local function audioWindow(summary: Recording, requested: AudioWindow?): ResolvedAudioWindow?
	local options: AudioWindow = requested or {}
	if summary.audio == nil then
		assert(options.start == nil and options.span == nil, "recording has no audio stream to sample")
		return nil
	end
	local start = options.start or 0
	assert(start == start and start >= 0 and start < summary.duration, "audio start must be within recording duration")
	local span = options.span or math.min(30, summary.duration - start)
	assert(span == span and span > 0 and span < math.huge, "audio span must be positive and finite")
	assert(start + span <= summary.duration, "audio window exceeds recording duration")
	return { start = start, span = span }
end

local function probeSummary(probe: Probe): Summary
	local format: { duration: (string | number)? } = probe.format or {}
	local duration = tonumber(format.duration)
	assert(duration ~= nil and duration > 0 and duration < math.huge, "recording has no positive duration")
	local video: ProbeStream? = nil
	local audio: ProbeStream? = nil
	local streams: { ProbeStream } = probe.streams or {}
	for _, stream in streams do
		if stream.codec_type == "video" and video == nil then
			video = stream
		elseif stream.codec_type == "audio" and audio == nil then
			audio = stream
		end
	end
	assert(
		video ~= nil and (video.width :: number) > 0 and (video.height :: number) > 0,
		"recording has no readable video dimensions"
	)
	return {
		duration = duration,
		video = {
			width = video.width :: number,
			height = video.height :: number,
			codec = video.codec_name,
			frameRate = video.avg_frame_rate,
		},
		audio = if audio ~= nil
			then { codec = audio.codec_name, channels = audio.channels, sampleRate = audio.sample_rate }
			else nil,
		audioSignal = if audio ~= nil then "unmeasured" else "no_audio_stream",
		visualJudgment = "unproved",
		audioJudgment = "unproved",
	}
end

local function audioMeasurement(log: string): AudioMeasurement
	return {
		maxVolumeDb = string.match(log, "max_volume: ([^ ]+) dB"),
		meanVolumeDb = string.match(log, "mean_volume: ([^ ]+) dB"),
		silenceDetected = string.find(log, "silence_start:", 1, true) ~= nil,
		thresholdDb = -50,
	}
end

local function sampleCommands(
	original: string,
	output: string,
	summary: Recording,
	requested: AudioWindow?
): { SampleCommand }
	local window = audioWindow(summary, requested)
	local samples: { SampleCommand } = {}
	for index, seconds in { 0, summary.duration / 2, math.max(0, summary.duration - 0.2) } do
		table.insert(samples, {
			kind = "frame",
			seconds = seconds,
			output = output .. "/frame-" .. tostring(index) .. ".png",
			argv = {
				"ffmpeg",
				"-nostdin",
				"-hide_banner",
				"-v",
				"error",
				"-n",
				"-ss",
				tostring(seconds),
				"-i",
				original,
				"-frames:v",
				"1",
				output .. "/frame-" .. tostring(index) .. ".png",
			},
		})
	end
	if window ~= nil then
		table.insert(samples, {
			kind = "audio",
			seconds = window.start,
			duration = window.span,
			output = output .. "/audio-sample.wav",
			argv = {
				"ffmpeg",
				"-nostdin",
				"-hide_banner",
				"-nostats",
				"-n",
				"-ss",
				tostring(window.start),
				"-i",
				original,
				"-t",
				tostring(window.span),
				"-map",
				"0:a:0",
				"-vn",
				"-af",
				"silencedetect=noise=-50dB:d=0.5,volumedetect",
				"-c:a",
				"pcm_s16le",
				output .. "/audio-sample.wav",
			},
		})
	end
	return samples
end

return {
	audioWindow = audioWindow,
	probeSummary = probeSummary,
	audioMeasurement = audioMeasurement,
	sampleCommands = sampleCommands,
}
