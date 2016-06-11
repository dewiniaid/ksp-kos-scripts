@LAZYGLOBAL off.
RUN ONCE lib_util.
// String formatting library.

// Note that KOS's string formatting performance is a bit.... lackluster.  Thus, the performance of this is probably not too great either.

// string comparisons, analogous to C's strcmp().
// These return -1, 0, or 1 based on whether a is less than, equal to, or greater than b.
FUNCTION str_cmpi {	// Case-insensitive.
	PARAMETER a.
	PARAMETER b.
	IF a < b { RETURN -1. }
	IF a > b { RETURN  1. }
	RETURN 0.
}

FUNCTION str_cmp {	// Case-sensitive.  Note this is based on raw unicode values; it is NOT collation-aware.  It is always safe to use this for testing equality, but ordering may otherwise be off.
	PARAMETER a.
	PARAMETER b.
	LOCAL r IS strcmpi(a,b).
	IF r<>0 {
		RETURN r.
	}
	// We can be reasonably assure the strings are the same length if we're still here... so iterate over characters.
	FOR ix IN RANGE(a:len) {
		IF a[ix] < b[ix] { RETURN -1. }
		IF a[ix] > b[ix] { RETURN 1. }
	}
	RETURN 0.
}
GLOBAL K_STR_DIGITS IS "0123456789".
// String to integer.
FUNCTION str_parse_int {
	PARAMETER s.
	SET s TO s:trim().
	LOCAL l IS s:length-1.
	LOCAL r IS 0.
	FOR ix IN RANGE(l, -1) {
		IF ix=0 {
			IF s[ix]="-" { RETURN -r. }
			IF s[ix]="+" { RETURN r. }
		}
		// UNCHAR() would be much faster, but doesn't appear to be working.
		LOCAL n IS K_STR_DIGITS:find(s[ix]).
		IF n=-1 {
			PRINT "*** Attempted to convert a non-integer string to an integer.  Causing an intentional exception to halt execution.".
			RETURN 1/0.
		}
		SET r TO r+(n * 10^(l-ix)).
	}
	RETURN r.
}

// Repeat a string N amount of times.
FUNCTION str_repeat {
	PARAMETER s. PARAMETER ct. 
	IF s=" " OR ct=0 { RETURN "":PadRight(ct). }
	RETURN "":PadRight(ct):Replace(" ", s).
}


// Format a number by removing its exponent (if any) and add the appropriate number of zeroes.
FUNCTION str_expand_e {
	PARAMETER v.
	SET v TO v:ToString().
	LOCAL pos IS v:find("E").
	IF pos<0 { RETURN v. }  // No exponent.
	LOCAL exp IS str_parse_int(v:substring(pos+1,v:length-pos-1)).
	LOCAL sign IS IIF(v[0]="-","-","").
	LOCAL v IS v:substring(sign:length, pos-sign:length).
	IF exp=0 { RETURN sign+v. }  // No exponent = no change.
	LOCAL pos IS v:find(".").
	// Remove decimal point and adjust
	IF pos<0 {
		SET pos TO 1+v:length.
	} ELSE {
		SET v TO v:remove(pos,1).
	}
	// Shift decimal exp places to the right (which may mean a left-shift if exp is negative).
	SET pos TO pos + exp.
	// v is now a bare number.
	// pos is at the (possibly out-of-bounds) index where a decimal point should be inserted.
	
	IF pos <= 0 { // Decimal point to the left of our bare number.
		RETURN sign + "0." + str_repeat("0", -pos) + v.
	}
	IF pos < v:length {
		RETURN sign + v:insert(pos,".").
	}
	RETURN sign + v + str_repeat("0", pos-v:length).
}

// Format a number by forcing it to contain an exponent (except in cases of 0).
// Note: If precision is applied, excess precision is truncated (not rounded)
FUNCTION str_force_e {
	PARAMETER v.
	PARAMETER p IS -1.  // Precision to maintain (-1 = auto).
	PARAMETER zeropad IS FALSE.  // Pad w/ trailing zeroes to force precision?
	IF v=0 { RETURN "0". }
	SET v TO v:ToString().
	IF v:contains("E") {
		IF p=-1 { RETURN v. }
		SET v TO str_expand_e(v).  // Needed so precision will apply.
	}
	LOCAL sign IS IIF(v[0]="-","-","").
	SET v TO v:remove(0,sign:length).
	LOCAL pos IS v:find(".").
	IF pos=1 AND v[0]<>"0" { RETURN sign+v. } // E+0, might as well keep as is.
	IF pos<0 {
		SET pos TO 1+v:length.
	} ELSE {
		SET v TO v:remove(pos,1).
	}
	LOCAL exp IS pos-1.
	IF exp=0 { // Starts with a zero, otherwise the earlier check would have happened instead.
		LOCAL t IS v:replace("0", " "):trimstart():replace(" ", "0").
		SET exp TO -(v:length - t:length).
		SET v TO t.
	}
	IF p>=0 AND p+1<v:length {	// Imposed precision limits
		SET v TO v:substring(0,p+1).
	} ELSE IF p>0 AND zeropad {
		SET v TO v:padright(p+1):replace(" ", "0").
	} ELSE IF p<0 AND exp>0 {
		SET v TO v:replace("0", " "):trimend():replace(" ", "0").
	}
		
	IF v:length > 1 { SET v TO v:insert(1,"."). }
	// We want to shift the decimal to be after the first digit.  The exponent is how large the shift is.
	RETURN sign + v + IIF(exp<0,"E","E+") + exp.
}

// String formatting.
// fmt is a 'format string'.  It is output as-is with some replacements, as noted by the below table.
// Note that the syntax is similar to Python's string formatting syntax, though not exactly the same.

// String escapes:
// \\ - Replaced with a single backslash.
// \{ - Replaced with a literal {.  Prevents variable expansion.
// \n - Replaced with CHAR(10) (newline)
// \r - Replaced with CHAR(13) (carriage return)
// \t - Replaced with CHAR(9) (horizontal tab)
// \' or \q - Replaced with CHAR(34) (double quotation mark)
// \123 - Replaced with CHAR(123).  May be any number of consecutive digits.
// \(123) - Replaced with CHAR(123).  Exists so \(123)1+1=2 is not ambigously parsed.
//
// Format string interpolation:
// Text within {} is treated as a reference to one of the passed arguments.  It uses the following convention:
// replacement_field ::=  "{" [field_name] ["!" transform] [":" format_spec] "}"
// 
// field_name:
// Refers to a field defined in args (which may either be a list or a lexicon).  If it is omitted, it is equivalent to specifying '0' the first time, '1' the second time, and so forth.
// Thus "{} {} {}" and "{0} {1} {2}" are equivalent.
//
// transform:
// One or more characters, in order:
// n: Assuming the field is a vector, reference its normalized form.
// x,y,z,m: Assuming the field is a vector, reference the corresponding axis value (or magnitude in the case of 'm'.  If any additional characters remain in the conversion string, they are applied to the resulting value.
// p,y,r: Assuming the field is a rotation, reference the correspinding yaw, pitch, or roll value,  Note that quaternions are rotations.
// s: Convert to string representation.
// t: Convert int or timespan to absolute time representation (i.e. a date+time)
// d: Convert int or timespan to relative time representation (i.e. days/hours from now)
//
// format_spec:
// For vectors and rotations, the format is applied to each component rather than the vector as a whole.
//
// format_spec ::=  [[fill]align][sign][["0"]width]["."["-"]precision]["/" options]
// fill        ::=  <any character>
// align       ::=  "<" | ">" | "=" | "^"  This is the default if the field width begins with a 0.
// sign        ::=  "+" | "-" | " "
// width       ::=  integer
// precision   ::=  integer
// 
// fill: If set, this is the character used for any padding.  If omitted, it is equivalent to space.
// align: < is left aligned, > is right aligned, = forces the padding to be placed after the sign (if any) but before any digits, "^" forces the field to be centered.
// sign: "-" uses a sign only on negative numbers (default).  "+" always use a sign.  " " use a leading space on positive numbers.
// width: Minimum field width for this value.  If this contains a leading 0, leading zeroes are added as padding as needed and align is set to =.  Width of 0 is the same as not specifying it at all.
// precision: For numeric types including vectors and rotations: number of digits to show after the decimal point.  For other types, this is a maximum field with (excess characters will be cut from the right of the string).
// If precision contains a leading minus sign, trailing zeros are replaced with spaces instead.  (Giving the illusion of aligning to decimal points.)
// options: Additional formatting options: 
// "l" labels vector and rotation components as x=/y=/z=/p=/y=/r=.  
// "d" is the same but expands pitch, yaw and roll.  
// "v" suppresses the output of V() and R() around vectors and directions.
// "e" forces all values to E notation.  Precision refers to the number of decimal points after the E
// "x" forces all values out of E notation, adding lots of zeroes.  Precision is ignored.
{
	// Internal utility to conver vector/direction to a list.
	FUNCTION _tolist {
		PARAMETER v.
		IF v:istype("Vector") { RETURN LIST(v:x, v:y, v:z). }
		IF v:istype("Direction") { RETURN LIST(v:pitch, v:yaw, v:roll). }
	}		
	
	// Applies the characters in transform to v, then passes it to fn.
	FUNCTION _fmt_transform {
		PARAMETER fn.
		PARAMETER transform.
		PARAMETER v.
		FOR ix IN RANGE(0, transform:length) {
			LOCAL c IS transform[ix].
			IF c="s" {
				SET v TO v:ToString().
			} ELSE IF v:isType("Vector") {
				IF c="n" { SET v TO v:normalized. }
				ELSE IF c="m" { SET v TO v:mag. }
				ELSE IF c="x" { SET v TO v:x. }
				ELSE IF c="y" { SET v TO v:y. }
				ELSE IF c="z" { SET v TO v:z. }
			} ELSE IF v:IsType("Direction") {
				IF c="p" { SET v TO v:pitch. }
				ELSE IF c="y" { SET v TO v:yaw. }
				ELSE IF c="r" { SET v TO v:roll. }
			} ELSE IF (v:IsType("Scalar") OR v:IsType("Timespan")) AND (c="d" OR c="t") {
				LOCAL dpy IS IIF(kuniverse:hoursperday=6,425,365).  // Here's to hoping KSP doesn't model leap years and we guessed correctly.
				LOCAL spd IS 3600*(kuniverse:hoursperday).
				LOCAL t IS ToSeconds(v).
				LOCAL sign IS IIF(t<0,"-", " ").
				SET t TO ABS(t).
				LOCAL s IS MOD(t, 60).
				IF c="d" {
					SET s TO FLOOR(s*100)*0.01.  // Round would be nicer, but might break terribly.
				} ELSE {
					SET s TO FLOOR(s).
				}
				LOCAL args IS LIST(
					FLOOR(t/(spd*dpy)) + IIF(c="t",1,0),
					FLOOR(MOD(t/spd, dpy)),
					FLOOR(MOD(t/3600, kuniverse:hoursperday)),
					FLOOR(MOD(t/60, 60)),
					s,
					sign
				).
				LOCAL ix IS 3.
				IF c="t" { SET ix TO 0. } // Abs time.
				ELSE IF args[0]>0 { SET ix TO 1. }
				ELSE IF args[1]>0 { SET ix TO 2. }
				RETURN _datefmts[ix](args).
			}
		}
		RETURN fn(v).
	}

	// Echo formatter: Simply returns the input value.
	FUNCTION _fmt_echo { PARAMETER v. RETURN v:ToString(). }
	
	// Formats component-carrying values like Vector and Direction.
	LOCAL _component_info IS LIST(
		// Type, prefix, suffix, shortlabels, longlabels
		LIST("Vector", "V(", ")", LIST("x=","y=","z="), LIST("x=","y=","z=")),
		LIST("Direction", "D(", ")", LIST("p=","y=","r="), LIST("pitch=","yaw=","roll="))
	).
	FUNCTION _fmt_components {
		PARAMETER v.
		PARAMETER label IS 0.
		PARAMETER wrap IS FALSE.
		PARAMETER values IS LIST().  // Overrides values on v if present.
		PARAMETER sep IS ", ".
		FOR ci IN _component_info {
			IF v:istype(ci[0]) {
				IF values:length=0 { SET values TO _tolist(v). }
				LOCAL r IS LIST().
				IF wrap { r:ADD(ci[1]). }
				FOR ix IN RANGE(values:length) {
					IF ix>0 AND sep<>"" { r:ADD(sep). }
					IF label { r:ADD(ci[label+2]). } 
					r:ADD(values[ix]).
				}
				IF wrap { r:ADD(ci[2]). }
				RETURN r:join("").
			}
		}
		RETURN v.
	}
	
	// Applies alignment options.
	FUNCTION _fmt_align {
		PARAMETER v.
		PARAMETER f IS " ".  // Fill character.
		PARAMETER a IS "a".  // Alignment.  Treated as > if set to "=".
		PARAMETER w IS 0.  // Width.
		PARAMETER p IS -1.  // Maxwidth (ONLY ON NESTED CALLS WITH STRINGS)

		// IF a="a" { SET a TO IIF(v:IsType("Scalar"), ">", "<"). }
		SET v TO v:ToString().
		LOCAL l IS v:Length.
		IF p<>-1 AND l>p {
			RETURN v:substring(0, p).
		}
		IF w=0 { RETURN v. }
		IF l>=w AND (p=-1 OR l<=p) { RETURN v. }
		IF a="<" { RETURN v + str_repeat(f, w-l). }  // Left
		IF a="^" { RETURN str_repeat(f, FLOOR((w-l)/2)) + v + str_repeat(f, CEIL((w-l)/2)). }   // Center
		RETURN str_repeat(f, w-l) + v.  // Right
	}
		
	// Formats a single component of a format string.  Does most of the heavy lifting
	FUNCTION _fmt {
		PARAMETER f IS " ".  // Fill character
		PARAMETER a IS "a".  // a for 'auto'.
		PARAMETER s IS "-".  // Sign
		PARAMETER w IS 0.  // Width
		PARAMETER p IS -1.  // Precision
		PARAMETER tz IS TRUE.  // Add trailing zeroes?
		PARAMETER clabel IS 0.  // 0: Don't label components.  1: Use first letter of component name.  2: Use entire component name.
		PARAMETER cwrap IS FALSE.  // TRUE: Add V() or R() if it makes sense.
		PARAMETER force_e IS FALSE.
		PARAMETER expand_e IS FALSE.
		PARAMETER v IS "".  // Value to format.
		
		IF v:istype("Vector") OR v:istype("Direction") {
			LOCAL components IS _tolist(v).
			FOR ix IN RANGE(components:length) {
				SET components[ix] TO _fmt(f,a,s,w,p,tz, clabel, cwrap, force_e, expand_e, components[ix]).
			}
			RETURN _fmt_components(v, clabel, cwrap, components).
		}
		IF v:istype("Scalar") {	// Whoo, all the hard stuff!
			IF force_e {
				RETURN _fmt_align(str_force_e(v,p,tz),f,a,w).
			}
			IF expand_e {
				SET v TO str_expand_e(v).
			} ELSE {
				IF p>=0 { SET v TO ROUND(v,p). }
				SET v TO  v:ToString().
			}
			LOCAL sign IS s.
			IF v:startswith("-") {
				SET sign TO "-".
				SET v TO v:remove(0,1).
			} ELSE IF s="+" AND v="0" {
				SET sign TO " ".
			} ELSE IF s="-" {
				SET sign TO "".
			}
				
			IF p>0 {
				// At 0 precision, we're rounded to an integer anyways.
				// At -1 precision, we don't care about decimal alignment.
				LOCAL pos IS v:IndexOf(".").  // Position of the decimal point.
				IF pos<0 { // Not found
					SET v TO v + IIF(tz, ".", " ").
					SET pos TO v:length-1.
				}
				SET v TO v + str_repeat(IIF(tz, "0", " "), p - (v:length-pos-1)).
			}
			IF a="=" { // Sign-align.
				RETURN sign + str_repeat(f, w-sign:length).
			}
			RETURN _fmt_align(sign + v,f,IIF(a="a",">",a),w).
		}
		RETURN _fmt_align(v,f,a,w,p).
	}
	
	FUNCTION _compileref {
		PARAMETER ref.
		LOCAL rlen IS ref:length.
		LOCAL exc IS ref:find("!").
		LOCAL colon IS ref:findat(":", IIF(exc<0,0,exc+1)).
		LOCAL var IS ref:substring(0, MIN(IIF(exc<0,rlen,exc),IIF(colon<0,rlen,colon))).
		LOCAL fconv IS IIF(exc<0,"",ref:substring(exc+1, IIF(colon<0,rlen,colon)-exc-1)).
		LOCAL fspec IS IIF(colon<0,"",ref:substring(colon+1, rlen-colon-1)).
		LOCAL fn IS _fmt_echo@.
		
		LOCAL width IS 0.
		LOCAL precision IS -1.
		LOCAL align IS "a".
		
		IF var<>"" {
			LOCAL isnum IS TRUE.
			FOR ix IN RANGE(var:length) {
				IF NOT K_STR_DIGITS:contains(var[ix]) {
					SET isnum TO FALSE.
					BREAK.
				}
			}
			IF isnum { SET var TO str_parse_int(var). }
		}
		
		// Handle the fieldspec.
		IF fspec<>"" {
			LOCAL ix IS 0.
			LOCAL fslen IS fspec:length.
			LOCAL fill IS "".  // If this is still empty at the end, we default it.
			LOCAL align IS "a".
			LOCAL sign IS "-".
			LOCAL tz IS true.
			IF fslen>1 AND "<>=^":contains(fspec[1]) {
				SET align TO fspec[1].
				SET fill TO fspec[0].
				SET ix TO 2.
			} ELSE IF "<>=^":contains(fspec[0]) {
				SET align TO fspec[0].
				SET ix TO 1.
			}
			IF ix<fslen AND "+- ":contains(fspec[ix]) {
				SET align TO fspec[ix].
				SET ix TO ix+1.
			}
			// Find width, precision, and options strings.
			LOCAL wstr IS "".
			LOCAL pstr IS "".
			LOCAL options IS "".
			LOCAL pdot IS fspec:findat(".", ix).
			LOCAL pslash IS fspec:findat("/", ix).
			SET wstr TO fspec:substring(ix, MIN(IIF(pdot<0,fslen,pdot),IIF(pslash<0,fslen,pslash))-ix).
			IF pdot>=0 AND (pdot<pslash OR pslash<0) AND pdot+1<fslen {
				SET pstr TO fspec:substring(pdot+1, IIF(pslash<0,fslen,pslash)-pdot-1).
			}
			IF pslash>=0 AND psplash+1<fslen {
				SET options TO fspec:substring(pslash+1, fslen-pslash-1).
			}
			IF wstr<>"" { SET width TO str_parse_int(wstr). }
			SET tz TO NOT (pstr<>"" AND pstr[0]="-").
			IF pstr<>"" { SET precision TO str_parse_int(pstr). }
			LOCAL clabel IS IIF(options:contains("d"),2,IIF(options:contains("l"),1,0)).
			LOCAL cwrap IS NOT options:contains("v").
			LOCAL expand_e IS options:contains("x").
			LOCAL force_e IS NOT expand_e AND options:contains("e").
			IF fill="" { SET fill TO IIF(wstr<>"" AND wstr[0]="0", "0", " "). }
			
			SET fn TO _fmt@:bind(fill, align, sign, width, precision, tz, clabel, cwrap, force_e, expand_e).
		}
		IF fconv<>"" {
			SET fn TO _fmt_transform@:bind(fn,fconv).
		}
		RETURN LIST(var, fn).
	}			

	// "compiles" a format string to reduce future processing time.
	// Returns a list that alternates between string -> argname -> delegate -> string -> argname -> delegate.
	LOCAL _replacements IS LEXICON("n", CHAR(10), "r", CHAR(13), "t", CHAR(9), "'", CHAR(34), "q", CHAR(34), "\", "\", "{", "{").
	LOCAL _cache IS LEXICON().
	LOCAL _cachemax IS 20.
	FUNCTION _compile {
		PARAMETER fmt.  // Format string
		PARAMETER usecache IS TRUE.  // Save results to cache.
		// We use a Very Naive Cache, where we remember up to _cachemax distinct calls to compile().
		// Rather than implement any logic to determine which element to expire if the cache gets full,
		// we simply void the entire cache.  Not super effective, but better than no cache at all.
		// Specialized cases can always call str_format_compile() directly and pass that around anyways.
		IF _cache:haskey(fmt) {
			RETURN _cache[fmt].
		}
		
		LOCAL argnum IS 0.
		LOCAL result IS LIST().	// Compiled result.
		LOCAL chunk IS LIST().	// Current const string result.
		LOCAL ix IS 0.
		LOCAL flen IS fmt:length.
		UNTIL false {
			// Find next backslash-escape or brace.
			LOCAL bs IS fmt:FINDAT("\", ix).
			LOCAL br IS fmt:FINDAT("{", ix).
			IF bs<0 AND br<0 {
				chunk:add(fmt:substring(ix, flen-ix)).
				result:add(chunk:join("")).
				IF usecache {
					IF _cache:length >= _cachemax {
						_cache:clear().
					}
					SET _cache[fmt] TO result.
				}
				RETURN result.
			}
			IF br<0 OR (bs>=0 AND bs<br) {
				// Backslash escape is the next sequence.
				IF bs>ix { chunk:add(fmt:substring(ix, bs-ix)). }
				IF bs+1>=flen { // There is no next character.
					PRINT "*** Incomplete backslash-escape at position " + bs + ".".
					RETURN 1/0.
				}
				IF NOT _replacements:haskey(fmt[bs+1]) {
					PRINT "*** Unknown backslash-escape '\" + fmt[bs+1] + "' at position " + bs + ".".
					RETURN 1/0.
				}
				chunk:add(_replacements[fmt[bs+1]]).
				SET ix TO bs+2.
			} ELSE {
				// Open brace is the next sequence.
				IF br>ix { chunk:add(fmt:substring(ix, br-ix)). }
				result:add(chunk:join("")).
				
				SET ix TO fmt:FINDAT("}", br+1)+1.
				IF ix<=0 {
					PRINT "*** Incomplete variable reference at position " + br + ".".
					RETURN 1/0.
				}
				LOCAL ref IS _compileref(fmt:substring(br+1, ix-br-2)).
				IF ref[0]="" {
					SET ref[0] TO argnum.
					SET argnum TO argnum+1.
				}
				SET chunk TO LIST().
				result:add(ref[0]).
				result:add(ref[1]).
			}
		}
	}
	
	FUNCTION _format {
		PARAMETER fmt.	// Format string
		PARAMETER args IS LIST().	// Replacement args.
		If fmt:IsType("String") { SET fmt TO _compile(fmt). }
		LOCAL l IS fmt:length.
		IF l=1 { RETURN fmt[0]. }
		LOCAL result IS LIST().
		FOR ix IN RANGE(0, l, 3) {
			result:add(fmt[ix]).
			IF ix+1<l { result:add(fmt[ix+2](args[fmt[ix+1]])). }
		}
		RETURN result:join("").
	}
	
	FUNCTION _formatter {
		PARAMETER fmt.
		If fmt:IsType("String") { SET fmt TO _compile(fmt, FALSE). }
		RETURN _format@:bind(fmt).
	}
		
	GLOBAL str_format IS _format@.
	GLOBAL str_formatter IS _formatter@.
	GLOBAL str_format_compile IS _compile@.

	LOCAL _datefmts IS LIST(
		str_formatter("Year {0}, day {1:03} {2:02}:{3:02}:{4:02}"),
		str_formatter("{5}{0}y,{1:03}d,{2:02}:{3:02}:{4:05.2}"),
		str_formatter("{5}{1}d,{2:02}:{3:02}:{4:05.2}"),
		str_formatter("{5}{2}:{3:02}:{4:05.2}")
	).
}
