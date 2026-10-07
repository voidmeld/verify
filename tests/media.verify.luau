--!strict

local Verify = require "../src/core"

local function summary(duration: number, audio: boolean?): Verify.MediaRecording
	return { duration = duration, audio = if audio == false then nil else {} }
end

local function refuses(callback: () -> ()): boolean
	return not pcall(callback)
end

return function(suite: Verify.Harness)
	suite:suite("media evidence", function()
		suite:case("defaults the audio window and clips it to the available audio", function(check)
			check:expect(Verify.mediaAudioWindow(summary(224.7))):toEqual { start = 0, span = 30 }
			check:expect(Verify.mediaAudioWindow(summary(12))):toEqual { start = 0, span = 12 }
			check:expect(Verify.mediaAudioWindow(summary(224.7), { start = 220 })):toEqual {
				start = 220,
				span = 224.7 - 220,
			}
			check:expect(Verify.mediaAudioWindow(summary(224.7, false))):toEqual(nil)
		end)

		suite:case("refuses past-end windows and explicit sampling without audio", function(check)
			local invalid: { Verify.MediaAudioWindow } = {
				{ start = -1 },
				{ start = 224.7 },
				{ start = math.huge },
				{ start = math.nan },
				{ span = 0 },
				{ span = -1 },
				{ span = math.huge },
				{ span = math.nan },
				{ start = 220, span = 5 },
			}
			for _, options in invalid do
				check
					:expect(refuses(function()
						Verify.mediaAudioWindow(summary(224.7), options)
					end))
					:toEqual(true)
			end
			check
				:expect(refuses(function()
					Verify.mediaAudioWindow(summary(224.7, false), { start = 0 })
				end))
				:toEqual(true)
		end)

		suite:case("keeps frame positions fixed while selecting later audio", function(check)
			local commands =
				Verify.mediaSampleCommands("original.mkv", "out", summary(224.7), { start = 150, span = 20 })
			check:expect(commands[1].seconds):toEqual(0)
			check:expect(commands[2].seconds):toEqual(224.7 / 2)
			check:expect(commands[3].seconds):toEqual(224.7 - 0.2)
			check:expect(commands[4].seconds):toEqual(150)
			check:expect(commands[4].duration):toEqual(20)
		end)

		suite:case("summarizes a probe without claiming visual or audible judgment", function(check)
			local video: Verify.MediaProbeStream =
				{ codec_type = "video", width = 64, height = 48, codec_name = "ffv1", avg_frame_rate = "10/1" }
			local audio: Verify.MediaProbeStream =
				{ codec_type = "audio", codec_name = "pcm_s16le", channels = 1, sample_rate = "48000" }
			local probe: Verify.MediaProbe = { format = { duration = "2.0" }, streams = { video, audio } }
			local result = Verify.mediaProbeSummary(probe)
			check:expect(result.video.width):toEqual(64)
			check:expect(result.audioSignal):toEqual "unmeasured"
			check:expect(result.visualJudgment):toEqual "unproved"
			check:expect(result.audioJudgment):toEqual "unproved"
			check
				:expect(refuses(function()
					Verify.mediaProbeSummary { format = { duration = "0" }, streams = {} }
				end))
				:toEqual(true)
			local measured =
				Verify.mediaAudioMeasurement "max_volume: -3.0 dB\nmean_volume: -20.5 dB\nsilence_start: 1.0"
			check:expect(measured.maxVolumeDb):toEqual "-3.0"
			check:expect(measured.silenceDetected):toEqual(true)
		end)
	end)
end
