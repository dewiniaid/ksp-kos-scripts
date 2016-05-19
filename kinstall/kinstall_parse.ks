@LAZYGLOBAL OFF.
RUN ONCE lib_kinstall.
FUNCTION KINSTALL_PARSE {
	PARAMETER file.
	PARAMETER vol IS core:currentvolume.
	PARAMETER minify IS FALSE.
	PARAMETER minify_comments IS KINSTALL_CONFIG["comments"].
	PARAMETER minify_lines IS KINSTALL_CONFIG["lines"].
	PARAMETER minify_space IS KINSTALL_CONFIG["space"].
	IF NOT minify {
		SET minify_comments TO FALSE.
		SET minify_lines TO 0.
		SET minify_space TO 0.
	} ELSE {
		IF minify_lines=-1 { SET minify_lines TO 2. }
		IF minify_space=-1 { SET minify_space TO 4. }
	}
	
	PRINT("Parsing " + file + " (on " + vol + ")").
	KINSTALL_STATUS("Parsing " + file, "Reading").
	
	// Current parser state.
	LOCAL InQ IS FALSE.	// Currently inside quotation marks?
	LOCAL AtLine IS 0.	// Current line of file.
	LOCAL AtChar IS 0.  // Current ch of line.
	LOCK MsgPrefix TO "File '" + file + "' near line " + AtLine + ", pos " + AtChar + ": ".
	
	// Character classifications.
	LOCAL Q is CHAR(34).// Quotation mark.
	// The operators here are technically, these are anything that a) can be have spaces collapsed and b) can break a 'word'.
	// 'e' is technically an operator, but cannot break a word so is ignored here.  
	LOCAL CharOperators IS ",+-*/^<>=:#".
	// Multicharacter operators.  FIXME: If any of these is <> 2 characters long, the parser code will need fixing since it assumes they're always length=2.
	LOCAL WordOperators IS "<> >= <=":SPLIT(" ").
	// Needed when handling whitespace collapses around operators.
	// < > (invalid syntax) cannot be collapsed to <>, but < -4 can be collapsed to <-4.
	// Even the 'non-collapsible' operators can be collapsed as long as they aren't adjacent.
	LOCAL CollapsibleOperators IS ",+-*/^:#".
	LOCAL Digits IS "0123456789".
	LOCAL IdentifierChars IS Digits + "_abcdefghijklmnopqrstuvwxyz".
	LOCAL BraceChars IS "{}[]()".
	
	// Result data.
	LOCAL Result IS LEXICON("run", LIST(), "ref", LIST(), "ops", LIST(), "data", LIST()).
	LOCAL Ops IS Result["ops"].
	LOCAL Data IS Result["data"].
	
	LOCAL RunDetectState IS 0.
	// RunDetectState:
	// 0: At a new instruction -- startup or immediately after EOS.
	// 1: Saw RUN
	// 2: Saw RUN <space>
	// 3: Saw RUN <space> ONCE
	// 4: Saw RUN <space> ONCE <space>
	// -1: Invalid state until next EOS.

	LOCAL FUNCTION RequiresSpace {
		// Returns TRUE if whitespace between the last instruction and a proposed op is required/affects its interpretation.
		PARAMETER op.
		PARAMETER val.
		IF Ops:Length=0 { RETURN false. }
		LOCAL ix IS Ops:Length-1.
		LOCK pop TO Ops[ix].
		LOCK pval TO Data[ix].
		LOCAL FUNCTION CheckConcat {
			RETURN NOT (
				(pop<>"NUM" OR (op<>"NUM" OR pval:contains(".")))
				AND (pop<>"SYM" OR (op<>"SYM" AND op<>"NUM"))
			).
		}
		IF (
			op="COM"	// Never needs space.
			OR pop="EOL" OR pop="SP" OR op="EOL" OR op="SP"	// Shouldn't happen anyways. 
			OR ((op="OP")<>(pop="OP"))	// One (but not both) are operators
			OR (op="OP" AND (CollapsibleOperators:Contains(val) OR CollapsibleOperators:Contains(pval)))
		) { RETURN false. }
		IF pop="EOS" {
			// This is a bit hairy because collapsing EOS may accidentally make floating point numbers and barewords.
			IF ix=0 { RETURN true. }
			SET ix TO ix-1.
		}
		RETURN CheckConcat().
	}
	
	LOCAL PendingSpace IS FALSE.	// Do we have a possible space we're waiting to add?

	FOR Line IN vol:open(file):readall() {
		SET AtLine TO AtLine + 1.
		KINSTALL_STATUS("Parsing " + file, "Line " + AtLine).
		SET AtChar TO 1.
		IF minify_space>0 {
			SET AtChar TO AtChar + Line:Length - Line:TrimStart():Length.
			SET Line To Line:Trim().
		}
		LOCAL ForceEOL IS (minify_lines=0).  // Force output of the EOL?
		LOCAL StartOfLine IS Ops:Length.  // Index of first token we added (in case we strip them later).
		
		FUNCTION ParseToken {
			// Parses a token of the input string.  
			// Returns LIST(op, number of characters consumed)  (-1 is 'all of them').
			// See also: https://github.com/KSP-KOS/KOS/blob/develop/src/kOS.Safe/Compilation/KS/Scanner.cs
			LOCAL ch IS Line[0].
			LOCAL pos IS 0.
			
			// Handle quoted strings.
			If InQ OR Ch = Q {
				If InQ {
					SET pos TO Line:Find(Q).
				} ELSE IF Line:Length > 1 {
					SET pos TO Line:FindAt(Q, 1).
				}
				SET InQ TO (pos = -1).  // If we didn't find a quote, we're still in a string.  Otherwise nope.
				IF NOT InQ { RETURN LIST("STR", pos + 1). }
				RETURN LIST("STR", pos).
			}
			
			// Handle comments.
			IF Line:StartsWith("//") {
				RETURN LIST("COM", -1).
			}
			
			// Handle whitespace.
			SET pos TO Line:Length - Line:TrimStart():Length.
			IF pos {
				RETURN LIST("SP", pos).
			}
			
			LOCAL FUNCTION GrabWhileContains {
				PARAMETER pos.
				PARAMETER s.
				UNTIL pos >= Line:Length OR NOT s:Contains(Line[pos]) {
					SET pos TO pos + 1.
				}
				RETURN pos.
			}
			
			// EOS or possible number.
			IF ch = "." {
				SET pos TO GrabWhileContains(1, Digits).
				IF pos=1 {
					RETURN LIST("EOS", 1).
				} ELSE {
					RETURN LIST("NUM", pos).
				}
			}
			// Number.
			IF Digits:Contains(ch) {
				SET pos TO GrabWhileContains(1, Digits).
				IF pos+1 < Line:Length AND Line[pos] = "." AND Digits:Contains(Line[pos+1]) {
					SET pos TO GrabWhileContains(pos+2, Digits).
				}
				RETURN LIST("NUM", pos).
			}
			// Symbol.  Symbols may contain numbers but can never start with one; that rule is handled by checking for numbers first.
			IF IdentifierChars:Contains(ch) {
				SET pos TO GrabWhileContains(1, IdentifierChars).
				UNTIL NOT (pos+1 < Line:Length AND Line[pos] = "." AND IdentifierChars:Contains(Line[pos+1])) {
					SET pos TO GrabWhileContains(pos+2, Digits).
				}
				RETURN LIST("SYM", pos).
			}
			
			// Braces.
			IF BraceChars:Contains(ch) {
				RETURN LIST("BRACE", 1).
			}
			
			// Operators.
			IF charoperators:CONTAINS(ch) {
				RETURN LIST("OP", 1).
			}
			IF Line:Length > 1 {
				LOCAL op IS Line:Substring(0, 2).
				If WordOperators:CONTAINS(op) {
					RETURN LIST("OP", 2).
				}
			}
			IF ch = "@" {
				RETURN LIST("AT", 1).
			}
			
			// Unknowns.
			KINSTALL_LOG("kinstall_parse", "warning", MsgPrefix + "Contains unknown token (ch='" + ch + "').").
			RETURN LIST("UNK", 1).
		}
		
		LOCAL val IS "".
		LOCAL op IS "".
		LOCAL EOL IS FALSE.
		UNTIL EOL OR Line:Length = 0 {
			LOCAL token IS ParseToken().
			IF token[1] = 0 {
				KINSTALL_LOG("kinstall_parse", "fatal", MsgPrefix + "Token was 0 length.  Aborting to avoid an infinite loop.").
				RETURN FALSE.
			}
			SET EOL TO token[1] = -1 OR token[1] >= Line:Length.
			SET op TO token[0].
			IF EOL {
				SET val TO Line.
			} ELSE {
				SET val TO Line:Substring(0, token[1]).
				SET Line TO Line:Substring(token[1], Line:Length - token[1]).
				SET AtChar TO AtChar + token[1].
			}
			IF minify_space>2 AND op="SP" {
				SET PendingSpace TO TRUE.
				SET val TO "".
			} ELSE IF op="COM" {
				IF minify_comments {
					SET val TO "".
				} ELSE IF minify_space>1 AND val:Length>2 {
					SET val TO "//" + val:Substring(2,val:Length-2):Trim().
				}
			}
			IF val<>"" {
				IF op="COM" { SET ForceEOL TO TRUE. }
				ELSE IF op<>"SP" { SET ForceEOL TO ForceEOL OR minify_lines<>2. }
				IF PendingSpace {
					IF minify_space<4 OR RequiresSpace(op, val) {
						Ops:Add(op).
						Data:Add(" ").
						IF (RunDetectState=1 OR RunDetectState=3) { SET RunDetectState TO RunDetectState+1. }
					} 
					// We might need to force a space after a EOS, so we keep it TRUE in that event.
					SET PendingSpace TO op="EOS" AND minify_space>3.
				}
				Ops:Add(op).
				Data:Add(val).
				// Catalog handling.
				IF op="EOS" {
					SET RunDetectState TO 0.
				} ELSE IF RunDetectState=-1 OR op="COM" {
					// noop
				} ELSE IF RunDetectState=0 AND op="SYM" AND val="RUN" {
					SET RunDetectState TO 1.
					
				} ELSE IF (
						((RunDetectState=1 OR RunDetectState=3) AND op="SP")
						OR (RunDetectState=2 AND op="SYM" AND val="ONCE")
				) {
					SET RunDetectState TO RunDetectState+1.
				} ELSE {
					IF (RunDetectState=2 OR RunDetectState=4) AND op="SYM" {
						IF val="ONCE" {
							KINSTALL_LOG("kinstall_parse", "warning", MsgPrefix + "Encountered RUN ONCE ONCE, which is likely to be invalid syntax.  Cataloging anyways.").
						}
						Result["run"]:Add(LIST(Ops:length-1, RunDetectState=4, val)).
					}
					SET RunDetectState TO -1.
				}
			}
		}
		IF InQ OR ForceEOL {
			Ops:Add("EOL").
			Data:Add(CHAR(10)).
		} ELSE IF minify_lines=1 {
			UNTIL StartOfLine=Ops:Length {
				Ops:Remove(Ops:Length-1).
			}
		} ELSE {
			SET PendingSpace TO TRUE.
		}
	}
	RETURN Result.
}
