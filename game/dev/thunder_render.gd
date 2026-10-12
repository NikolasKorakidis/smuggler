extends SceneTree
## Renders thunder for a close and a far strike to WAV files (to listen to):
## godot --headless --path game -s res://dev/thunder_render.gd -- <out_dir>
func _init() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	var wa := WeatherAudio.new(Weather.new(), null)
	for c in [["close_400m", Vector3(400, 0, 0), true], ["mid_3km", Vector3(3000, 0, 0), true],
			["far_9km", Vector3(9000, 0, 0), true], ["in_cloud_5km", Vector3(5000, 2500, 0), false]]:
		var job := {}
		var t0 := Time.get_ticks_msec()
		wa._synth_thunder(job, c[1], c[2], 1.0, 1200.0, Vector3(0, 3, 0), 7)
		var wav: AudioStreamWAV = job.result
		var secs := wav.data.size() / 2.0 / WeatherAudio.RATE
		print("%-14s %.1f s long, arrives after %.1f s, %.0f dB, made in %d ms" % [c[0], secs, job.first_arrival, job.db, Time.get_ticks_msec() - t0])
		wav.save_to_wav(out.path_join(c[0] + ".wav"))
	wa.free()
	quit()
