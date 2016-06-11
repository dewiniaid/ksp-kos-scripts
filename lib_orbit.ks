@LAZYGLOBAL OFF.
RUN ONCE lib_util.
RUN ONCE lib_basis.
// Orbital calculation and prediction functions.
// 
// For convenience, we track our own orbit info in a lexicon.  By convention (to separate it from kOS's orbit structure), we abbreviate it as "orb" rather than "obt".

// Orbit lexicons are created from an existing orbit using orb_from_orbit() or from position and velocity vectors using orb_from_vectors().
// They contain the following elements:

// KEPLERIAN ELEMENTS (and reference data):
// body:  Reference body.
// epoch: Reference time.
// ecc:   Eccentricity (e)
// sma:   Semimajor axis (a)
// inc:   Inclination. (i)
// argp:  Argument of Periapsis. (w)
// lan:   Longitude of Ascending Node (omega)
// mna:   Mean anomaly at epoch. (M0)

// DERIVED ELEMENTS (that are not time-based)
// o ap:    Apoapsis.  Unlike KSP apoapsis, this includes the body radius.
// o pe:    Periapsis.  Unlike KSP periapsis, this includes the body radius.
// o period: Orbital period.
// o smna:  Semi-minor axis. (b)
// o hev:   Hyperbolic Excess Velocity (v-infinity)
// d mu:    Shortcut to body:mu.
// d slr:   Semi-latus rectum. (l)
// d arate: Mean angular rate.

// TEMPORAL ELEMENTS (time-based, relative to defined epoch).
// e eccanomaly: Eccentric Anomaly; or hyperbolic anomaly if e>1
// t trueanomaly: True Anomaly.
// l lat:   Latitude.
// l lon:   Longitude.
// r rmag:  Radius.  (More accurate than r:mag).
// r r:     Position vector relative to body. (SOI-RAW rather than SHIP-RAW.  Sort of.).
// v vmag:  Orbital speed  (More accurate than v:mag).
// v v:     Velocity vector.


FUNCTION orb_from_orbit {
	PARAMETER o IS obt.
	PARAMETER t IS TIME.
	IF o:istype("lexicon") { RETURN o. }
	SET t TO ToTime(t).
	IF o:istype("orbitable") { SET o TO ORBITAT(o, t:seconds). }
	WAIT 0.
	LOCAL r IS RELPOSITION(obt).
	LOCAL v IS obt:velocity:orbit.
	// Create most of the initial orbit parameters, and then change epoch to our reference time.
	// See github.com/KSP-KOS/KOS/issues/1665 for why we can't just use obt:meananomalyatepoch.
	LOCAL mna IS orb_convert_anomaly(obt:trueanomaly,obt:eccentricity,KA_TRUE,KA_MEAN).
	LOCAL orb IS orb_update(LEXICON(
		"body", obt:body,
		"ecc", obt:eccentricity,
		"sma", obt:semimajoraxis,
		"inc", obt:inclination,
		"lan", obt:lan,
		"argp", obt:argumentofperiapsis,
		"mna", mna,
		"epoch", time,
		"period", obt:period,
		"ap", obt:apoapsis + obt:body:radius,
		"pe", obt:periapsis + obt:body:radius,
		"mu", obt:body:mu,
		"trueanomaly", obt:trueanomaly,
		"rmag", r:mag,
		"smna", obt:semiminoraxis,
		"r", r,
		"vmag", v:mag,
		"v", v
	), "d").
	orb_update(orb, "etrv").
	//IF t=TIME {
	//	orb_update(orb, "etrv").
	//} ELSE {
	orb_set_time(orb, t).
	//}
	RETURN orb.
}

// Converts an anomaly from one type to another.
// Returns FALSE on a failed conversion.  (Use IsFalse() to check return values, since 0 is also a valid return).
FUNCTION orb_convert_anomaly {
	PARAMETER m.   // Input anomaly
	PARAMETER e.   // Input eccentricity.
	PARAMETER have IS KA_MEAN.  // Anomaly type of input.
	PARAMETER want IS KA_ECC.   // Anomaly type of output.
	IF have=want { RETURN m. }  // No conversion needed.

	IF e<=1 {
		SET m TO Clamp360(m).
		IF e=0 OR m=0 OR m=180 { RETURN m. }
		IF m>180 { RETURN 360-orb_convert_anomaly(360-m,e,have,want). }
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
		
// (Re)calculates derived and temporal elements from the orbit.
FUNCTION orb_update {
	PARAMETER o.
	PARAMETER what IS "etrv".  // Determines which parameters to recalculate.  By default, only temporal parameters.
	IF what:contains("*") {
		SET what TO "odetrvl".
	}
	
	SET o["mu"] TO o["body"]:mu.
	IF what:contains("o") {
		LEX_UPDATE(o, LEXICON(
			"ap", (1+o["ecc"])*o["sma"],
			"pe", ABS(o["ecc"]-1)*o["sma"],
			"smna", ABS(o["sma"])*SQRT(ABS(1-o["ecc"]^2))
		)).
	}
	IF what:contains("d") {
		IF o["ecc"]>1 {
			LEX_UPDATE(o, LEXICON(
				"hev", SQRT(o["mu"]/-o["sma"]),
				"departureangle", 2*arccos(-1/o["ecc"]),
				"period", 2*K_PI*(1/SQRT(o["mu"] / ABS(o["sma"])^3))
			)).
		} ELSE {
			LEX_UPDATE(o, LEXICON(
				"hev", 0,
				"departureangle", 0,
				"period", 2*K_PI*SQRT((o["sma"])^3 / o["mu"])
			)).
		}
		SET o["arate"] TO o["period"]/360.
		SET o["slr"] TO o["smna"]^2/o["sma"].
	}
	IF what:contains("e") {  // Eccentric anomaly
		SET o["eccanomaly"] TO orb_convert_anomaly(o["mna"], o["ecc"]).
	}
	IF what:contains("t") {  // True anomaly.
		SET o["trueanomaly"] TO orb_convert_anomaly(o["eccanomaly"], o["ecc"], KA_ECC, KA_TRUE).
		// IF o["eccanomaly"]>180 { SET o["trueanomaly"] TO 360-o["trueanomaly"]. }
	}
	IF what:contains("r") {  // Position vector.
		SET o["rmag"] TO o["sma"]*(1-o["ecc"]^2)/(1+o["ecc"]*COS(o["trueanomaly"])).
		//LOCAL i IS IIF(Clamp360(o["trueanomaly"]+o["argp"])>180,o["inc"],-o["inc"]).
		LOCAL p IS 0.
		IF o["ecc"] > 1 {
			SET p TO V(o["sma"]*(COSH(o["eccanomaly"])-o["ecc"]), 0, o["smna"]*SINH(o["eccanomaly"])).
		} ELSE {
			SET p TO V(o["sma"]*(COS(o["eccanomaly"])-o["ecc"]), 0, o["smna"]*SIN(o["eccanomaly"])).
		}
		SET o["r"] TO AngleAxis2(
			AngleAxis2(
				p,
				V(COS(-o["argp"]),0,SIN(-o["argp"])),
				o["inc"]  //IIF(Clamp360(o["argp"]+o["trueanomaly"])>180,-o["inc"],o["inc"])
			),
			K_Y, -o["argp"] + solarprimevector:direction:yaw - 90 - o["lan"]
		).
		IF (o["r"]:y<0)<>(CLAMP360(o["argp"]+o["trueanomaly"])>180) {
			SET o["r"]:y TO -o["r"]:y.
		}
	}
	IF what:contains("v") {  // Velocity vector.
		SET o["vmag"] TO SQRT(o["mu"]*(2/o["rmag"]-1/o["sma"])).
		// Can't directly calculate velocity; so compare positions in a 1-second window centered on our epoch.
		// Make sure we don't ask those calculations to include a velocity.
		LOCAL prev IS orb_at_time(o, o["epoch"]-0.5, "etr").
		LOCAL next IS orb_at_time(o, o["epoch"]+0.5, "etr").
		SET o["v"] TO next["r"]-prev["r"].
	}
	RETURN o.
}

// Changes the epoch of an orbit, updating MNA and other parameters accordingly.
FUNCTION orb_set_time {
	PARAMETER o.
	PARAMETER t IS TIME.
	PARAMETER calc IS "etrv".  // What to recalculate after epoch change.
	SET t TO ToTime(t).
	
	IF t=o["epoch"] { RETURN o. }
	LOCAL m IS o["mna"] + (ToSeconds(t)-ToSeconds(o["epoch"]))/o["arate"].
	IF o["ecc"]<=1 { SET m TO Clamp360(m). }
	SET o["mna"] TO m.  // Clamp360(o["mna"] + o["arate"]*Mod((t-o["epoch"]):seconds,o["period"])).   // , o["period"])*360/o["period"]).
	SET o["epoch"] TO t.
	RETURN orb_update(o, calc).
}

// Duplicate an orbit and set it to the specified time.
FUNCTION orb_at_time {
	PARAMETER o.
	PARAMETER t IS TIME.
	PARAMETER calc IS "etrv".  // What to recalculate after epoch change.
	IF o:IsType("Lexicon") {
		RETURN orb_set_time(o:copy(), t, calc).
	} ELSE {
		RETURN orb_from_orbit(o, t).
	}
}

// Shortcut to orb_at_time(o,orb_next_anomaly(m,o,t,have)).
FUNCTION orb_at_anomaly {
	PARAMETER m.  // Anomaly value.
	PARAMETER o IS obt.
	PARAMETER t IS TIME.  // Time must be greater than this value.
	PARAMETER have IS KA_TRUE.
	RETURN orb_at_time(o,orb_next_anomaly(m,o,t,have)).
}
	
// Create orbit from state vectors.
FUNCTION orb_from_vectors {
	PARAMETER r IS RELPOSITION(obt).
	PARAMETER v IS obt:velocity:orbit.
	PARAMETER b IS body.
	PARAMETER t IS TIME.
	
	LOCAL h IS VCRS(r, v).	// Angular momentum.
	LOCAL mu IS b:mu.
	LOCAL evec IS ((v:SQRMAGNITUDE - mu/r:mag) * r - (r*v)*v).	// Eccentricity.
	LOCAL ecc IS evec:mag / mu.	// Eccentricity.
	LOCAL n IS v(h:z, 0, -h:x).  // Node vector.
	LOCAL argp IS ACOSL((evec*n)/(evec:mag*n:mag), evec:y).
	LOCAL mult IS IIF(r*v < 0, -1, 1).
	LOCAL ta IS ACOSL(evec*r/(evec:mag*r:mag),mult).  // True anomaly
	//LOCAL ea IS ACOS((ecc+COS(ta))/(1+ecc*COS(ta)),mult).  // Ecc anomaly
	LOCAL ea IS orb_convert_anomaly(ta, ecc, KA_TRUE, KA_ECC).
	
	// Orbital energy.
	// LOCAL e IS (v:mag^2)/2 - (mu/r:mag).	// Energy.
	// LOCAL a IS -mu/(2*((v:mag^2)/2 - (mu/r:mag))).	// Semi-major axis.
	// LOCAL p IS a*(1-ecc^2).	// Parameter, semi-latus rectum
	RETURN orb_update(LEXICON(
		"body", b,
		"ecc", ecc,
		"sma", -mu/(2*((v:SQRMAGNITUDE)/2 - (mu/r:mag))),
		"inc", 180 - ACOS(h:y/h:mag),  // Inclination.  0=polar, 90=equatorial.
		"lan", ACOS(n:x/n:mag, n:z) - ACOS(solarprimevector:x, solarprimevector:z),
		"argp", ACOS((evec*n)/(evec:mag*n:mag), evec:y),
		// "mna", Clamp360(mult * K_DEGREES * (ea/K_DEGREES - ecc*SIN(ea))),
		"mna", orb_convert_anomaly(ea, ecc, KA_ECC, KA_MEAN),
		"epoch", ToTime(t),
		"trueanomaly", ta,
		"eccanomaly", ea,
		"rmag", r:mag,
		"r", r,
		"vmag", v:mag,
		"v", v
	), "od").
}

// Returns one of two anomaly values where a particular altitude will occur.
// (Subtract the result from 360 to get the other possible answer).
//
// To minimize the effects of fp-error, values < PE will return 0, values > AP will return 180.
// Must be pe <= r <= ap
FUNCTION orb_anomaly_at_radius {
	PARAMETER r.
	PARAMETER o IS obt.
	PARAMETER want IS KA_TRUE.
	SET o TO orb_from_orbit(o).
	IF r < (o["pe"]) RETURN 0.
	IF r > (o["ap"]) AND o["ecc"]<=1 RETURN 180.
	
	LOCAL v IS ((((o["sma"]*(1-o["ecc"]^2))/r) - 1)/o["ecc"]).
	RETURN orb_convert_anomaly(ACOSL(v), o["ecc"], KA_TRUE, want).
}

FUNCTION orb_radius_for_anomaly {
	PARAMETER m.  // Anomaly value.
	PARAMETER o IS obt.
	PARAMETER have IS KA_TRUE.  // Anomaly type
	SET o TO orb_from_orbit(o).
	RETURN o["sma"]*(1-o["ecc"]^2)/(1+o["ecc"]*COS(orb_convert_anomaly(m,o,have,KA_TRUE))).
}

// Returns the next time a particular anomaly value will be reached.
// (Hint: Time to periapsis = orb_next_anomaly(0,...); time to apoapsis = orb_next_anomaly(180,...).
// **NOTE: Hyperbolic orbits will only visit each anomaly once.  This returns that visit time, which may be in the past.**
FUNCTION orb_next_anomaly {
	PARAMETER m.  // Anomaly value.
	PARAMETER o IS obt.
	PARAMETER t IS TIME.  // Time must be greater than this value.
	PARAMETER have IS KA_TRUE.
	SET o TO orb_from_orbit(o).
	SET m TO orb_convert_anomaly(m, o["ecc"], have, KA_MEAN).
	IF IsFalse(m) { RETURN false. }
	SET t TO ToSeconds(t).
	// Figure out where MNA is "now".
	LOCAL mnow IS o["mna"] + (ToSeconds(t)-ToSeconds(o["epoch"]))/o["arate"].
	IF o["ecc"]<=1 {
		SET m TO Clamp360(m).
		SET mnow TO Clamp360(mnow).
		IF m<mnow { SET m TO 360+m. }
	}
	RETURN t + (m-mnow)*o["arate"].
}

FUNCTION orb_prev_anomaly {
	PARAMETER m.  // Anomaly value.
	PARAMETER o IS obt.
	PARAMETER t IS TIME.  // Time must be greater than this value.
	PARAMETER have IS KA_TRUE.
	SET o TO orb_from_orbit(o).
	RETURN orb_next_anomaly(m,o,t-o["period"],have).
}

// Returns a predicted orbit based on a maneuver node.
FUNCTION orb_predict {
	PARAMETER o.  // Orbit.
	PARAMETER n.  // Node or RNP Vector.
	PARAMETER t IS TIME.  // Time.  Ignored if node.
	IF n:IsType("Node") {
		SET t TO TIME+n:eta.
		SET n TO node_to_vector(n).
	}
	LOCAL o IS orb_at_time(o,t).
	RETURN orb_from_vectors(o["r"], o["v"] + basis_transform(basis_mvr(o), n, True), o["body"], t).
}

// Returns latitude at a particular anomaly value.
// I derived this one myself!
// sin(lat) = sin(true + argp) * cos(90 - inc)
FUNCTION orb_latitude_for_anomaly {
	PARAMETER m.  // Anomaly value.
	PARAMETER o IS obt.
	PARAMETER have IS KA_TRUE.
	SET o TO orb_from_orbit(o).
	SET m TO orb_convert_anomaly(m, o["ecc"], have, KA_TRUE).
	RETURN ASINL(SIN(m+o["argp"]) * SIN(o["inc"])).
}

// Returns expected anomaly value for a particular latitude.
FUNCTION orb_anomaly_at_latitude {
	PARAMETER lat.
	PARAMETER o IS obt.
	PARAMETER want IS KA_TRUE.  // Desired return anomaly type.
	PARAMETER alt IS FALSE.  // Return other alternate anomaly value.
	SET o TO orb_from_orbit(o).
	IF alt {
		RETURN orb_convert_anomaly(-ASINL(SIN(lat)/COS(90-o["inc"])) + 180 - o["argp"], o["ecc"], KA_TRUE, want).
	}
	RETURN orb_convert_anomaly(ASINL(SIN(lat)/COS(90-o["inc"])) - o["argp"], o["ecc"], KA_TRUE, want).
}
