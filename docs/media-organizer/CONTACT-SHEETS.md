# Interactive video contact sheets (F05, first slice)

In the local/SD/USB video viewer, choose **Frames** or press **V** after the video
has initialized. Playback pauses. The dialog samples 12 bucket-center timestamps;
6 or 24 previews can be selected after generation finishes. Tap a preview/time to
seek the same active video. Playback stays paused until the user resumes it.
Native decoders may return a nearby keyframe, so previews are not exact-frame
editing boundaries. Short timestamps include milliseconds where needed.

Frames are generated sequentially at bounded thumbnail size through the existing
native frame API. No subprocess, thumbnail file, catalog entry or temporary file
is introduced. Encoded buffers belong to the dialog; closing, stopping or leaving
the foreground evicts its memory-image entries and wipes its encoded buffers.
Late results are discarded and wiped. This is best-effort cleanup of these
buffers, not a guarantee about codec, GPU, OS or compromised-process memory.

The host verifies that the active video/controller and storage root still match
before seeking. Text fields retain V for text entry, and disabled/locked viewer
controls cannot open the dialog. Explicit thumbnail times now survive the native
low-resolution fallback; opening-frame replacement is disabled for explicit times.
Reviewed thumbnail diagnostics no longer include filenames, image dimensions or
exception messages, even when optional debug logging is enabled.

Eight planning/widget cases cover interval boundaries, invalid metadata, seek
targets, cancellation, backgrounding, stale-video refusal and frame-buffer
cleanup. A shared viewer-control case covers V, text focus and disabled controls.
All pass in the 3,911-test integrated Flutter suite. Real codecs/SAF/Samsung
hardware still need acceptance testing. Image export, in/out selection, scene
sampling, subtitle overlays and storyboard walls remain future work.
