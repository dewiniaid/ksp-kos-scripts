@LAZYGLOBAL OFF.
RUN ONCE lib_kinstall.
RUN ONCE kinstall_parse.
// Deploy scripts to a craft.  Performs limited minification and other space-saving optimizations.  Identifies dependencies.

FUNCTION KINSTALL {
	PARAMETER file.
	PARAMETER dest IS core:volume.
	PARAMETER source IS archive.
	PARAMETER cfg IS KINSTALL_CONFIG.
	LOCAL source_files IS source:files.

	FUNCTION CGET {
		// Get from our config (or the default)
		PARAMETER k.
		IF cfg:haskey(k) { RETURN cfg[k]. }
		RETURN KINSTALL_CONFIG[k].
	}
	
	// Load configuration.
	LOCAL sanity IS CGET("sanity").
	LOCAL tempvol IS source.
	IF KINSTALL_CONFIG:haskey("tempvol") {
		SET tempvol TO CGET("tempvol").
	}
	
	// LOCAL opt_recurse IS CGET("recurse").
	// LOCAL opt_fileref IS CGET("fileref"). // NYI
	LOCAL opt_compile IS CGET("compile").
	LOCAL opt_inplace IS CGET("inplace").
	LOCAL opt_minify IS CGET("minify").
	LOCAL minify_comments IS CGET("comments").
	LOCAL minify_lines IS CGET("lines").
	LOCAL minify_space IS CGET("space").
	LOCAL opt_cleanup IS CGET("cleanup").
	LOCAL opt_ks_as_ksm IS CGET("ks_as_ksm").
	LOCAL opt_ksm_as_ks IS CGET("ksm_as_ks").
	
	IF sanity {
		IF dest=archive {
			KINSTALL_LOG("kinstall", "fatal", "Refusing to use the archive as a destination.  Set the 'sanity' key to false to disable this check.").
			RETURN FALSE.
		}
	}
	
	LOCAL prev IS core:currentvolume.
	
	LOCAL tempprefix IS "_kinstall." + ROUND(time:seconds) + ".".
	LOCAL tempct IS 0.
	FUNCTION tempname {
		PARAMETER ext IS ".ks.tmp".
		PARAMETER vol IS tempvol.
		SET tempct TO tempct+1.
		UNTIL NOT vol:exists(tempprefix+tempct+ext) {
			SET tempct TO tempct+1.
		}
		LOCAL fn IS tempprefix+tempct+ext.
		RETURN fn.
	}
	
	SWITCH TO source.
	LOCAL FileParseQueue IS QUEUE().
	LOCAL FileTypeCache IS LEXICON().
	LOCAL SourceFiles IS source:files.
	LOCAL ParsedFiles IS LEXICON().
	LOCAL Strategies IS LEXICON().  // Strategies are for actual files.

	LOCAL FUNCTION FileType {
		PARAMETER fn.
		IF NOT FileTypeCache:HasKey(fn) {
			IF NOT SourceFiles:HasKey(fn) {
				SET FileTypeCache[fn] TO "".
			} ELSE {
				LOCAL type IS Source:Open(fn):ReadAll():Type.
				SET FileTypeCache[fn] TO type.
				IF type="KSM" AND NOT fn:endswith(".ksm") {
					KINSTALL_LOG("kinstall", "warning", "KSM file with non-.ksm extension: " + fn).
				} ELSE IF type="KS" AND fn:endswith(".ksm") {
					KINSTALL_LOG("kinstall", "warning", "KS text file with .ksm extension: " + fn).
				} ELSE IF type="BINARY" {
					KINSTALL_LOG("kinstall", "warning", "File appears to be binary: " + fn).
				}
			}
		}
		RETURN FileTypeCache[fn].
	}
	
	LOCAL FUNCTION safeToOverwrite {
		PARAMETER fn.
		PARAMETER vol IS archive.
		
		RETURN vol<>archive OR fn:contains(tempprefix) OR NOT source_files:contains(fn).
	}
	LOCAL FUNCTION copyAndRename {
		PARAMETER srcvol.
		PARAMETER srcfile.
		PARAMETER dstvol.
		PARAMETER dstfile IS "".
		IF dstfile = "" {
			SET dstfile TO srcfile.
		}
		LOCAL description IS "While copying '" + srcvol + "':'" + srcfile + "' to '" + dstvol + "':'" + dstfile + ": ".

		// Check for self-copy.
		IF srcfile = dstfile AND srcvol = dstvol {
			KINSTALL_LOG("kinstall", "warning", description + "Cannot copy a file to itself.").
			RETURN false.
		}
		// Check for sanity.
		IF NOT safeToOverwrite(dstfile, dstvol) {
			IF sanity {
				KINSTALL_LOG("kinstall", "error", description + "Sanity is enabled.  Will not overwrite non-temporary files on archive.").
				RETURN false.
			}
			KINSTALL_LOG("kinstall", "warning", description + "Overwriting previous file on archive.").
		}
		
		// If the filenames match, we can do a direct COPY.
		IF srcfile = dstfile {
			SWITCH TO dstvol.
			COPY srcfile FROM srcvol.
			SWITCH TO curvol.
			RETURN true.
		}
		
		// Do read+write copy.
		LOCAL data IS srcvol:open(srcfile):readall.
		dstvol:delete(dstfile).
		dstvol:create(dstfile):write(data).
		RETURN true.
	}
	LOCAL FUNCTION writeMinifyData {
		PARAMETER srcfile.
		PARAMETER dstvol.
		PARAMETER dstfile IS "".
		IF dstfile = "" {
			SET dstfile TO srcfile.
		}
		LOCAL description IS "While writing '" + dstvol + "':'" + dstfile + ": ".
		
		IF srcfile = dstfile AND source = dstvol {
			KINSTALL_LOG("kinstall", "warning", description + "Will not write minified code on top of original source.").
			RETURN false.
		}
		// Check for sanity.
		IF NOT safeToOverwrite(dstfile, dstvol) {
			IF sanity {
				KINSTALL_LOG("kinstall", "error", description + "Sanity is enabled.  Will not overwrite non-temporary files on archive.").
				RETURN false.
			}
			KINSTALL_LOG("kinstall", "warning", description + "Overwriting previous file on archive.").
		}
		dstvol:delete(dstfile).
		LOCAL prev IS core:currentvolume.
		SWITCH TO dstvol.
		LOG ParsedFiles[srcfile]["data"]:join("") TO dstfile.
		SWITCH TO prev.
	}
	LOCAL msgPrefix IS "(init) ".

	LOCAL FUNCTION Process {
		PARAMETER ref.
		LOCAL fn IS ref.
		LOCAL p IS fn:Find(".").
		IF p=ref:FindLast(".") AND (ref:endswith(".ksm") OR ref:endswith(".ks")) {
			SET fn TO ref:substring(0, p).
		}
		LOCAL base IS fn.
		LOCAL Type IS FileType(fn).
		IF p=-1 OR Type="" {
			SET fn TO fn+".ks".
			SET Type TO FileType(fn).
			IF Type="" {
				SET fn TO fn+"m".
				SET Type TO FileType(fn).
			}
		}
		IF Type="" {
			KINSTALL_LOG("kinstall", "warning", msgPrefix + "File '" + ref + "' does not exist on the source.").
			RETURN ref.
		}
		IF fn<>ref AND ref:contains(".") {
			KINSTALL_LOG("kinstall", "warning", msgPrefix + "Reference file '" + ref + "' resolved to different file '" + fn + "')").
		}
		IF Strategies:haskey(fn) {
			RETURN base.
		}
		IF Type="ksm" {
			KINSTALL_LOG("kinstall", "info", msgPrefix + "Found KSM ref '" + ref + "' ('" + fn + "')").
			SET Strategies[fn] TO "asis".
			RETURN base.
		}
		KINSTALL_LOG("kinstall", "info", msgPrefix + "Adding KS ref '" + ref + "' ('" + fn + "') to queue.").

		FileParseQueue:Push(fn).
		IF NOT opt_compile OR base:contains(".") {
			IF opt_compile {
				KINSTALL_LOG("kinstall", "warning", msgPrefix + "Won't attempt compilation of non-standard filename '" + ref + "'.").
			}
			IF opt_minify {
				SET Strategies[fn] TO "ks".
			} ELSE {
				SET Strategies[fn] TO "asis".
			}
		} ELSE {
			SET Strategies[fn] TO "auto".
		}
		RETURN base.
	}
	
	Process(file).
	
	UNTIL FileParseQueue:LENGTH=0 {
		SET file TO FileParseQueue:POP().
		SET msgPrefix TO "(in " + file + ") ". 
		SET ParsedFiles[file] TO KINSTALL_PARSE(file, source, opt_minify, minify_comments, minify_lines, minify_space).
		FOR entry IN ParsedFiles[file]["run"] {
			SET ParsedFiles[file]["data"][entry[0]] TO Process(entry[2]).
		}
	}
	IF Strategies:Length=0 {
		KINSTALL_LOG("kinstall", "fatal", "Nothing to do, possibly due to missing files.").
		RETURN.
	}
	
	LOCAL Volmap IS LEXICON(source, "src", dest, "dst").
	IF NOT Volmap:Haskey(tempvol) { SET Volmap[tempvol] TO "tmp". }
	LOCAL FUNCTION Action {
		PARAMETER act.
		PARAMETER sv.
		PARAMETER sf.
		PARAMETER dv IS archive.
		PARAMETER df IS "".
		LOCAL msg IS ACT + " " + Volmap[sv] + "/" + sf.
		IF df<> "" { SET msg TO msg + " => " + Volmap[dv] + "/" + df. }
	}
	
	LOCAL FUNCTION HandleStrategy {
		PARAMETER fn.
		LOCAL Strat IS Strategies[fn].
		
		IF Strat="asis" OR (NOT opt_minify AND (Strat="ks" OR NOT opt_compile)) {
			Action("COPY", source, fn, dest, fn).
			COPY fn TO Dest.
			RETURN 0.
		}
		
		LOCAL origsize IS source_files[fn]:size.
		LOCAL szlen IS (""+origsize):length.
		LOCAL kssize IS origsize.

		PRINT "Original: " + (""+origsize):padleft(szlen) + "  [" + fn + "]".
		
		IF strat="ks" {
			Action("MINIFY", source, fn, dest, fn).
			writeMinifyData(fn, dest, fn).
			SET kssize TO dest:files[fn]:size.
			PRINT "Minified: " + (""+kssize):padleft(szlen).
			RETURN origsize-kssize.
		}
		
		// Figure out the name for KSM files.
		LOCAL ksm IS fn.
		IF fn:endswith(".ks") AND fn:find(".")=fn:findlast(".") {
			SET ksm TO fn+"m".
		} ELSE IF fn:find(".")=-1 {
			SET ksm TO fn+".ksm".
		}
		LOCAL ksmtemp IS ksm.
		LOCAL kstemp IS fn.
		
		IF (source<>tempvol OR opt_minify) AND dest<>tempvol {
			SET kstemp TO tempname().
		}
		IF opt_minify {
			Action("MINIFY", source, fn, tempvol, kstemp).
			writeMinifyData(fn, tempvol, kstemp).
		} ELSE IF source<>tempvol {
			Action("COPY", source, fn, tempvol, kstemp).
			CopyAndRename(source, fn, tempvol, kstemp).
		}
		IF NOT opt_inplace AND dest<>tempvol {
			SET ksmtemp TO tempname().
		}
		SWITCH TO tempvol.
		Action("COMPILE", tempvol, kstemp, tempvol, ksmtemp).
		COMPILE kstemp TO ksmtemp.
		
		IF opt_minify {
			SET kssize TO tempvol:files[kstemp]:size.
			PRINT "Minified: " + (""+kssize):padleft(szlen).
		}
		LOCAL ksmsize IS tempvol:files[ksmtemp]:size.
		PRINT "Compiled: " + (""+ksmsize):padleft(szlen) + "  [" + ksm + "]".
		IF kssize <= ksmsize {
			IF opt_minify {
				PRINT "Using minified version.".
			} ELSE {
				PRINT "Keeping original version.".
			}
			IF opt_cleanup AND ksmtemp<>ksm {
				Action("DELETE", tempvol, ksmtemp).
				tempvol:delete(ksmtemp).
			}
			IF tempvol<>dest {
				IF opt_cleanup {
					Action("MOVE", tempvol, kstemp, dest, fn).
				} ELSE {
					Action("COPY", tempvol, kstemp, dest, fn).
				}
				CopyAndRename(tempvol, kstemp, dest, fn).
				IF opt_cleanup { tempvol:delete(kstemp). }
			} ELSE IF kstemp<>fn {
				Action("RENAME", tempvol, ksmtemp, tempvol, ksm).
				RENAME FILE kstemp TO fn.
			}
			RETURN origsize-kssize.
		} ELSE {
			PRINT "Using compiled version.".
			IF opt_cleanup AND (kstemp<>fn OR source<>tempvol) {
				Action("DELETE", tempvol, kstemp).
				tempvol:delete(kstemp).
			}
			IF tempvol<>dest {
				IF opt_cleanup AND NOT opt_inplace  {
					Action("MOVE", tempvol, ksmtemp, dest, ksm).
				} ELSE {
					Action("COPY", tempvol, ksmtemp, dest, ksm).
				}
				CopyAndRename(tempvol, ksmtemp, dest, ksm).
				IF opt_cleanup AND NOT opt_inplace { tempvol:delete(kstemp). }
			} ELSE IF ksmtemp<>ksm {
				Action("RENAME", tempvol, ksmtemp, tempvol, ksm).
				RENAME FILE ksmtemp TO ksm.
			}
			RETURN origsize-ksmsize.
		}
	}
	
	PRINT "Executing plans for " + Strategies:Length + " file(s).".
	FOR File IN Strategies:keys {
		HandleStrategy(file).
	}
}
