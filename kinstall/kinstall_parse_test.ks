RUN ONCE kinstall_parse.
LOCAL oldipu IS CONFIG:IPU.
SET CONFIG:IPU TO KINSTALL_CONFIG["IPU"].
PRINT "Starting KINSTALL test mode.".

FUNCTION RunTest {
	PARAMETER description.
	PARAMETER prefix.
	PARAMETER parse.
	LOCAL v IS core:currentvolume.
	
	PRINT "Running test: " + description.
	
	IF NOT prefix:startswith("test_") {
		SET prefix TO "test_" + prefix.
	}
	
	LOCAL t IS time:seconds.
	LOCAL result IS parse().
	PRINT "Parse completed; pseudotime=" + (time:seconds - t) + "; ops=" + result["ops"]:length.
	LOCAL fn IS prefix + ".json".
	WRITEJSON(result, fn).
	PRINT "Wrote " + fn.
	
	SET fn TO prefix + ".ks".
	core:currentvolume:delete(fn).
	LOG result["data"]:join("") TO fn.

	LOCAL f IS v:open(fn).
	PRINT ".ks Size: " + f:size() + "  (File: " + fn + ")".
	UNSET f.
	
	LOCAL ksm IS fn + "m".
	COMPILE fn TO ksm.
	PRINT ".ksm Size: " + v:open(ksm):size() + "  (File: " + ksm + ")".
	PRINT "End of test.".
}

LOCAL p IS KINSTALL_PARSE@:bind("kinstall_parse.ks", core:currentvolume).
SWITCH TO 0.
RunTest("Parse", "test_minify_off", p).
SET p TO p:bind(TRUE).
RunTest("Minify noop", "test_minify_noop", p:bind(FALSE, 0, 0)).
RunTest("Minify nocomments", "test_minify_nocomment", p:bind(TRUE, 0, 0)).
RunTest("Minify trim", "test_minify_trim", p:bind(TRUE, 0, 1)).
RunTest("Minify reduce", "test_minify_reduce", p:bind(TRUE, 0, 3)).
RunTest("Minify nospace", "test_minify_nospace", p:bind(TRUE, 0, 4)).
RunTest("Minify noblank", "test_minify_noblank", p:bind(TRUE, 1, 1)).
RunTest("Minify collapse", "test_minify_collapse", p:bind(TRUE, 2, 3)).
RunTest("Minify max", "test_minify_max", p:bind(TRUE, 2, 4)).

SET CONFIG:IPU TO oldipu.