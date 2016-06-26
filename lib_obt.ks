@LAZYGLOBAL OFF.
RUN ONCE lib_util.
RUN ONCE lib_basis.
RUN ONCE lib_iter.
// Orbital calculation and prediction functions.

FUNCTION obt_of { PARAMETER o. IF o:IsType("Orbit") { RETURN o. } RETURN o:obt. }

// Converts an anomaly (or list of anomalies) from one type to another.
// Returns FALSE on a failed conversion.  (Use IsFalse() to check return values, since 0 is also a valid return).
FUNCTION obt_convert_anomaly {
	PARAMETER m.   // Input anomaly
	PARAMETER e.   // Input eccentricity -- or an orbit lexicon.
	PARAMETER have IS KA_MEAN.  // Anomaly type of input.
	PARAMETER want IS KA_ECC.   // Anomaly type of output.

	IF have=want { RETURN m. } // No conversion needed.  Even if m happens to be a list.
	IF e:IsType("Lexicon") { SET e TO e["ecc"]. }
	ELSE IF e:IsType("Orbitable") { SET e TO e:obt:eccentricity. }
	ELSE IF e:IsType("Orbit") { SET e TO e:eccentricity. }
	IF m:IsType("List") {
		LOCAL result IS LIST().
		FOR item IN m { result:add(obt_convert_anomaly(item, e, have, want)). }
		RETURN result.
	}
	IF e<=1 {
		SET m TO Clamp360(m).
		IF e=0 OR m=0 OR m=180 { RETURN m. }
		IF m>180 { RETURN 360-obt_convert_anomaly(360-m,e,have,want). }
	}
	LOCAL s IS IIF(m<0,-1,1).	// Sign.
	IF have=KA_MEAN { // Converting from mean -> eccentric -> maybe true.
		LOCAL ok IS 0.  // Set to 1 upon converge.
		LOCAL o IS m*s.
		IF e>1 {
			// Hyperbolic orbit, computing hyperbolic anomaly.
			// Based on solving algorithm listed here: http://www.projectpluto.com/kepler.htm
			LOCAL r IS o/K_DEGREES.  // Mean anomaly in radians.
			LOCAL d IS 0.  // Delta ('error')
			SET m TO r/(e-1).
			IF m^2 > 6*(e-1) {
				if o<180 {
					SET m TO (6*r)^(1/3).
				} ELSE {
					SET m TO ASINH(o/e)/K_DEGREES.
				}
			}
			FOR _ IN RANGE(100) {
				//  err = ecc * sinh( curr) - curr - mean_anom;
				SET d TO e*SINH(m*K_DEGREES)-m-r.
				IF ABS(d)<K_EPSILON { SET ok TO 1. BREAK. }
				SET m TO m-d/(e*COSH(m*K_DEGREES)-1).
			}
			IF ok=0 {
				PRINT str_format("*** Failed to converge on hyperbolic anomaly (inputs: mean={}, ecc={}) ***", LIST(s*o,e)).
			}
			SET m TO s*m*K_DEGREES.
		} ELSE {
			// Elliptical (possibly circular) orbit.
			// Implemented from [A Practical Method for Solving the Kepler Equation]
			// by Marc A. Murison from the U.S. Naval Observatory
			// See: http://murison.alpheratz.net/dynamics/twobody/KeplerIterations_summary.pdf
			// (Ported from https://github.com/RazerM/orbital/blob/0.7.0/orbital/utilities.py#L252 )
			LOCAL r IS m/K_DEGREES.  // Mean anomaly in radians.
			SET m TO r+(e^3/2+e+(e^2+1.5*cos(m)*e^3)*cos(m))*sin(m).	// Starting guess
			FOR _ IN RANGE(100) {
				LOCAL p IS m.	// Store previous guess
				LOCAL c IS COS(m*K_DEGREES).	
				LOCAL s IS SIN(m*K_DEGREES).
				LOCAL f IS e*s+r-m.
				LOCAL z IS f/(f*e*s/2/(e*c-1)+e*c-1).
				SET m TO m-f/((s/2-c*z/6)*e*z+e*c-1).
				IF ABS(m-p)<K_EPSILON { SET ok to 1. BREAK. }
			}
			IF ok=0 {
				PRINT str_format("*** Failed to converge on eccentric anomaly (inputs: mean={}, ecc={}) ***", LIST(o,e)).
			}
			SET m TO m*K_DEGREES.
			IF m<0 OR m>=360 {
				PRINT str_format("*** Clamp may be needed for eccentric anomaly (inputs: mean={}, ecc={}, output: {}) ***", LIST(o,e,m)).
				SET m TO Clamp360(m).  // TODO: See if the clamp is even neccessary.
			}
		}
	} ELSE IF have=KA_TRUE { // Converting from true -> eccentric -> maybe mean.
		LOCAL v IS ((e+cos(s*m))/(1+e*cos(s*m))).
		IF e>1 AND v<=-1 {
			PRINT str_format("*** No solution for true anomaly (inputs: true={}, ecc={}; v: {}) ***", LIST(m,e,v)).
			RETURN FALSE.
		}
		SET m TO s*IIF(e>1,ACOSH@,ACOS@)(v).
	}
	// If we're here, we have an eccentric anomaly.  Which direction are we converting?
	IF want=KA_MEAN {
		IF e>1 {	// Hyperbolic.
			RETURN K_DEGREES*(e*SINH(m)-m/K_DEGREES).
		}
		RETURN K_DEGREES*(m/K_DEGREES-e*SIN(m)).
	}
	IF want=KA_TRUE {
		LOCAL c IS IIF(e>1,COSH@,COS@)(m).
		RETURN ACOS((c-e)/(1 - e*c)).
	}
	RETURN m.
}

// Returns one of two anomaly values where a particular altitude will occur.
// (Subtract the result from 360 to get the other possible answer).
// To minimize the effects of fp-error, values < PE will return 0, values > AP will return 180.
FUNCTION obt_anomaly_at_radius {
	PARAMETER r.
	PARAMETER o IS obt.
	PARAMETER want IS KA_TRUE.
	SET o TO obt_of(o).
	IF r <= o:periapsis+o:body:radius { RETURN 0. }
	IF r >= o:apoapsis+o:body:radius { RETURN 180. }
	RETURN obt_convert_anomaly(ACOSL(((o:semimajoraxis*(1-o:eccentricity^2))/r - 1)/o:eccentricity), o, KA_TRUE, want).
}

FUNCTION obt_anomalies_at_radius {
	PARAMETER r.
	PARAMETER o IS obt.
	PARAMETER want IS KA_TRUE.
	LOCAL m IS obt_anomaly_at_radius(r,o,want).
	RETURN LIST(m,360-m).
}

FUNCTION obt_next_radius {
	PARAMETER r.
	PARAMETER o IS obt.
	PARAMETER t IS TIME.
	
	RETURN obt_next_anomalies(obt_anomalies_at_radius(r,o), o, t).
}

// Returns radius at a particular anomaly value.
FUNCTION obt_radius_at_anomaly {
	PARAMETER m.  // Anomaly value.
	PARAMETER o IS obt.
	PARAMETER have IS KA_TRUE.  // Anomaly type
	SET o TO obt_of(o).
	RETURN o:semimajoraxis*(1-o:eccentricity^2)/(1+o:eccentricity*COS(obt_convert_anomaly(m,o,have,KA_TRUE))).
}

// Returns the next time a particular anomaly value will be reached.
// (Hint: Time to periapsis = obt_next_anomaly(0,...); time to apoapsis = obt_next_anomaly(180,...).
// **NOTE: Hyperbolic orbits will only visit each anomaly once.  This returns that visit time, which may be in the past.**
FUNCTION obt_next_anomaly {
	PARAMETER m.  // Anomaly value.
	PARAMETER o IS obt.
	PARAMETER t IS TIME.  // Time must be greater than this value.
	PARAMETER have IS KA_TRUE.
	IF m:IsType("List") {
		RETURN obt_next_anomalies(m,o,t,have).
	}
	SET o TO obt_of(o).
	SET m TO obt_convert_anomaly(m, o, have, KA_MEAN).
	IF IsFalse(m) { RETURN false. }
	LOCAL mnow IS obt_convert_anomaly(o:trueanomaly, o, KA_TRUE, KA_MEAN).
	//SET t TO ToSeconds(t)-ToSeconds(TIME).
	IF o:eccentricity<=1 {
		SET m TO Clamp360(m).
		SET mnow TO Clamp360(mnow).
		IF m<mnow { SET m TO 360+m. }
	}
	RETURN ToSeconds(t) + (m-mnow)*(o:period/360).
}

// Returns the next time one of the listed anomalies will be reached.
// **NOTE: Hyperbolic orbits will only visit each anomaly once.  If all candidate anomalies are in the past, returns False.**
FUNCTION obt_next_anomalies {
	PARAMETER anoms.  // Anomaly values.
	PARAMETER o IS obt.
	PARAMETER t IS TIME.  // Time must be greater than this value.
	PARAMETER have IS KA_TRUE.
	SET o TO obt_of(o).
	LOCAL mnow IS obt_convert_anomaly(o:trueanomaly, o, KA_TRUE, KA_MEAN).
	LOCAL best IS FALSE.
	LOCAL init IS FALSE.
	IF o:eccentricity<=1 { SET mnow TO Clamp360(mnow). }
		
	FOR m IN obt_convert_anomaly(anoms, o, have, KA_MEAN) {
		IF NOT IsFalse(m) {
			IF o:eccentricity<=1 {
				SET m TO Clamp360(m).
				IF m<mnow { SET m TO 360+m. }
			}
			IF m>=mnow AND (NOT init OR m<best) {
				SET best TO m.
				SET init TO TRUE.
			}
		}
	}
	IF NOT init { RETURN false. }
	RETURN ToSeconds(t) + (best-mnow)*(o:period/360).
}

// Old version, maintained for now.
FUNCTION obt_earliest_anomaly {
	PARAMETER anoms.  // Anomaly values.
	PARAMETER o IS obt.
	PARAMETER t IS TIME.  // Time must be greater than this value.
	PARAMETER have IS KA_TRUE.
	LOCAL mnow IS obt_anomaly_at_time(t, o, have).
	LOCAL m IS FALSE.
	IF o:eccentricity<=1 {
		FOR anom IN anoms {
			IF IsFalse(m) OR Clamp360(m-mnow) > Clamp360(anom-mnow) { SET m TO anom. }
		}
	} ELSE {
		FOR anom IN anoms {
			IF anom>=mnow AND (IsFalse(m) OR (m-mnow) > (anom-mnow)) { SET m TO anom. }
		}
	}
	IF IsFalse(m) { RETURN m. }
	RETURN obt_next_anomaly(m,o,t,have).
}	

// Returns the previous time an anomaly was reached.
FUNCTION obt_prev_anomaly {
	PARAMETER m.  // Anomaly value.
	PARAMETER o IS obt.
	PARAMETER t IS TIME.  // Time must be greater than this value.
	PARAMETER have IS KA_TRUE.
	SET o TO obt_of(o).
	RETURN obt_next_anomaly(m,o,t-o:period,have).
}

// Returns what the anomaly is at a particular time.
FUNCTION obt_anomaly_at_time {
	PARAMETER t IS TIME.  // Time must be greater than this value.
	PARAMETER o IS obt.
	PARAMETER want IS KA_TRUE.
	SET o TO obt_of(o).
	LOCAL mnow IS obt_convert_anomaly(o:trueanomaly, o, KA_TRUE, KA_MEAN).
	LOCAL m IS mnow + 360*(ToSeconds(t)-ToSeconds(TIME))/o:period.
	IF o:eccentricity<=1 { SET m TO Clamp360(m). }
	RETURN obt_convert_anomaly(m,o,KA_MEAN, want).
}
	
// Returns latitude at a particular anomaly value.
// I derived this one myself!
// sin(lat) = sin(true + argp) * cos(90 - inc)
FUNCTION obt_latitude_at_anomaly {
	PARAMETER m.  // Anomaly value.
	PARAMETER o IS obt.
	PARAMETER have IS KA_TRUE.
	SET o TO obt_of(o).
	SET m TO obt_convert_anomaly(m, o, have, KA_TRUE).
	RETURN ASINL(SIN(m+o:argumentofperiapsis) * SIN(o:inclination)).
}

// Returns expected anomaly value for a particular latitude.
FUNCTION obt_anomaly_at_latitude {
	PARAMETER lat.
	PARAMETER o IS obt.
	PARAMETER want IS KA_TRUE.  // Desired return anomaly type.
	PARAMETER alternate IS FALSE.  // Return other alternate anomaly value.
	SET o TO obt_of(o).
	LOCAL m IS o:argumentofperiapsis.
	IF lat=0 { // LAN/LDN special case.
		SET m TO IIF(alternate, 180, 0)-m.
	}
	ELSE IF lat=o:inclination {	// North special case.
		SET m TO 90-m.
	} ELSE IF lat=-o:inclination {	// South special case.
		SET m TO 270-m.
	} ELSE IF alternate {
		SET m TO (180-ASINL(SIN(lat)/COS(90-o:inclination))) - m.
	} ELSE {
		SET m TO ASINL(SIN(lat)/COS(90-o:inclination)) - m.
	}
	IF o:eccentricity<=1 { SET m TO Clamp360(m). }
	RETURN obt_convert_anomaly(m, o:eccentricity, KA_TRUE, want).
}

// Returns both anomaly values for a particular latitude.  Slightly faster than calling the above twice.
FUNCTION obt_anomalies_at_latitude {
	PARAMETER lat.
	PARAMETER o IS obt.
	PARAMETER want IS KA_TRUE.  // Desired return anomaly type.
	PARAMETER useabs IS FALSE.  // Also include -lat.
	PARAMETER dir IS 0.  // Postive: Return highest result.  Negative: Return lowest result.  0: Return all results.
	
	SET o TO obt_of(o).
	LOCAL m IS LIST().
	LOCAL argp IS o:argumentofperiapsis.
	IF lat=0 { // LAN/LDN special case.
		SET m TO LIST(-argp, 180-argp).
	} ELSE IF ABS(lat)=o:inclination { // North/South special case
		IF lat>0 OR useabs { m:ADD(90 - argp). }
		IF lat<0 OR useabs { m:ADD(270 - argp). }
	} ELSE {
		LOCAL x IS ASINL(SIN(lat)/COS(90-o:inclination)).
		m:ADD(x - argp).
		m:ADD((180-x) - argp).
		IF useabs {
			m:ADD(-x - argp).
			m:ADD(180+x - argp).
		}
	}
	IF o:eccentricity<=1 { iter_map(Clamp360@, m). }
	
	IF dir<0 { SET m TO obt_lowest_anomaly(m). }
	ELSE IF dir>0 { SET m TO obt_lowest_anomaly(m). }
	
	RETURN obt_convert_anomaly(m, o:eccentricity, KA_TRUE, want).
}

GLOBAL obt_highest_anomaly IS iter_nearest@:bind(180).
GLOBAL obt_lowest_anomaly IS iter_furthest@:bind(180).

// Time this latitude will next be reached.
FUNCTION obt_next_latitude {
	PARAMETER lat.  // Desired latitude.
	PARAMETER o IS obt.
	PARAMETER t IS TIME.  // Time must be greater than this value.
	PARAMETER useabs IS FALSE.  // Also allow -lat.
	PARAMETER dir IS 0.  // Postive: Higher altitude.  Negative: Lower altitude.  Zero: Either.
	RETURN obt_next_anomaly(obt_anomalies_at_latitude(lat, o, KA_TRUE, useabs, dir), o, t).
	IF dir<>0 {
		IF lat=0 { // Fast LAN/LDN special case.
			RETURN obt_next_anomaly(IIF(BETWEEN(90, o:argumentofperiapsis, 270)=(dir>0), 180, 0) - o:argumentofperiapsis,o,t).
		}
		IF useabs {
			// at 0<=argp<180, pe is in the north, thus ap is in the south (negative latitudes are higher).
			SET lat TO IIF(BETWEEN(0, argp, 180)=(dir>0), -1, 1)*ABS(lat).
			SET useabs TO FALSE.
		}
	}
	
	SET o TO obt_of(o).
	if o:inclination < ABS(lat) {
		PRINT str_format("*** Latitude {} will never be reached in an orbit of inclination {}", LIST(lat, o:inclination)).
		RETURN FALSE.
	}
	LOCAL anoms IS obt_anomalies_at_latitude(lat, o).
	IF useabs AND lat<>0 {
		Extend(anoms, obt_anomalies_at_latitude(-lat, o)).
	}
	IF dir>0 {
		RETURN obt_next_anomaly(obt_highest_anomaly(anoms)).
	}
	IF dir<0 {
		RETURN obt_next_anomaly(obt_lowest_anomaly(anoms)).
	}
	RETURN obt_next_anomalies(anoms).
}

// Synodic period between this orbit and either a target orbit or a set period.
FUNCTION obt_synodic_period {
	PARAMETER p1.
	PARAMETER o IS obt.
	
	IF p1:IsType("Orbitable") {
		SET p1 TO p1:obt:period.
	} ELSE IF p1:IsType("Orbit") {
		SET p1 TO p1:period.
	} ELSE {
		SET p1 TO ToSeconds(other).
	}
	LOCAL p2 IS obt_of(o):period.
	
	RETURN 1/(1/MIN(p1,p2) - 1/MAX(p1,p2)).
}
	

// Convenience functions
{
	FUNCTION _wa { PARAMETER have. PARAMETER want. PARAMETER m. PARAMETER e. RETURN obt_convert_anomaly(m,e,have,want). }
	GLOBAL anom_m2e IS _wa@:bind(KA_MEAN, KA_ECC).
	GLOBAL anom_m2t IS _wa@:bind(KA_MEAN, KA_TRUE).
	GLOBAL anom_e2m IS _wa@:bind(KA_ECC, KA_MEAN).
	GLOBAL anom_e2t IS _wa@:bind(KA_ECC, KA_TRUE).
	GLOBAL anom_t2m IS _wa@:bind(KA_TRUE, KA_MEAN).
	GLOBAL anom_t2e IS _wa@:bind(KA_TRUE, KA_ECC).
	
	FUNCTION _wt { 
		PARAMETER fn.
		PARAMETER t IS TIME.
		PARAMETER o IS obt. 
		RETURN fn(obt_anomaly_at_time(t,o),o).
	}
	GLOBAL obt_latitude_at_time IS _wt@:bind(obt_latitude_at_anomaly@).
	GLOBAL obt_radius_at_time IS _wt@:bind(obt_radius_at_anomaly@).
}
