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
// d mu:    Shortcut to body:mu.
// d slr:   Semi-latus rectum. (l)

// TEMPORAL ELEMENTS (time-based, relative to defined epoch).
// e eccentricanomaly: Eccentric Anomaly.
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


FUNCTION orb_convert_anomaly {
	PARAMETER m.   // Input anomaly
	PARAMETER e.   // Input eccentricity.
	PARAMETER have IS KA_MEAN.  // Anomaly type of input.
	PARAMETER want IS KA_ECC.   // Anomaly type of output.
	PARAMETER attempts IS 100.  // Max attempts for iterative conversions (mean->not mean)
	SET m TO Clamp360(m).
	IF m=0 OR m=180 OR e=0 OR have=want { RETURN m. }  // No conversion needed.
	IF m>180 { RETURN 360-orb_convert_anomaly(360-m, e, have, want, attempts). }

	IF have=KA_MEAN { // Converting from mean.  Needs at least eccentric.
		LOCAL lower IS m.
		LOCAL upper IS 180.
		IF DEFINED(eccentric_anomaly_table) {
			// Faster calculations if we have the anomaly table loaded.
			LOCAL t IS eccentric_anomaly_table.
			LOCAL r IS FLOOR(e*T:length).
			LOCAL c IS FLOOR(m/180 * T[0]:length).
			SET upper TO t[r][c].
			IF r>0 AND c>0 { SET lower TO t[r-1][c-1]. }
		}
		LOCAL guess IS (lower+upper)/2.
		SET m TO m/K_DEGREES.
		FOR _ IN RANGE(attempts) {
			SET guess TO (lower+upper)/2.
			LOCAL err IS (guess/K_DEGREES - e*SIN(guess))-m.
			IF ABS(err) < 1e-15 { BREAK. }
			IF err > 0 {
				SET upper TO guess.
			} ELSE {
				SET lower TO guess.
			}
		}
		SET m TO guess.
	} ELSE IF have=KA_TRUE { // Converting from true anomaly.
		SET m TO ACOS((e+COS(m))/(1+e*COS(m))).
	}
	// If we're here, we have an eccentric anomaly.  Which direction are we converting?
	IF want=KA_MEAN {
		RETURN Clamp360(K_DEGREES * (m/K_DEGREES - e*SIN(m))).
	} ELSE IF want=KA_TRUE {
		RETURN Clamp360(ACOS((COS(m)-e)/(1-e*COS(m)))).
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
			"pe", (1-o["ecc"])*o["sma"],
			"ap", (1+o["ecc"])*o["sma"],
			"period", 2*constant():pi*SQRT(o["sma"]^3 / o["body"]:mu),
			"smna", ABS(o["sma"]*SQRT(1 - o["ecc"]^2))
		)).
	}
	IF what:contains("d") {
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
		LOCAL i IS IIF(o["trueanomaly"]>180,o["inc"],-o["inc"]).
		SET o["r"] TO AngleAxis2(
			AngleAxis2(
				V(o["sma"]*(COS(o["eccanomaly"])-o["ecc"]), 0, o["smna"]*SIN(o["eccanomaly"])),
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
	SET o["mna"] TO Clamp360(o["mna"] + MOD((t-o["epoch"]):seconds, o["period"])*360/o["period"]).
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
	LOCAL argp IS ACOS((evec*n)/(evec:mag*n:mag), evec:y).
	LOCAL mult IS IIF(r*v < 0, -1, 1).
	LOCAL ta IS ACOS(evec*r/(evec:mag*r:mag),mult).  // True anomaly
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
// Must be pe <= r <= ap
FUNCTION orb_anomaly_at_radius {
	PARAMETER r.
	PARAMETER o IS obt.
	PARAMETER want IS KA_TRUE.
	SET o TO orb_from_orbit(o).
	
	IF r < (o["pe"]) OR r > (o["ap"]) {
		PRINT "*** WARNING: attempted to find true anomaly where pe <= radius <= ap is false.".
		RETURN.
	}
	LOCAL v IS ((((o["sma"]*(1-o["ecc"]^2))/r) - 1)/o["ecc"]).
	RETURN orb_convert_anomaly(ACOSE(v), o["ecc"], KA_TRUE, want).
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
FUNCTION orb_next_anomaly {
	PARAMETER m.  // Anomaly value.
	PARAMETER o IS obt.
	PARAMETER t IS TIME.  // Time must be greater than this value.
	PARAMETER have IS KA_TRUE.
	SET o TO orb_from_orbit(o).
	SET m TO orb_convert_anomaly(m, o["ecc"], have, KA_MEAN).
	SET t TO ToSeconds(t).
	
	LOCAL adelta IS Clamp360(m-o["mna"])/360*o["period"].  // Fractional time required to get from current MNA to target.
	LOCAL orbits IS FLOOR((t-o["epoch"]:seconds)/o["period"]).  // Number of whole orbits required to get to current time from epoch time.
	LOCAL result IS o["epoch"] + (orbits*o["period"]) + adelta.
	IF result<t { RETURN ToTime(result+o["period"]). }
	RETURN ToTime(result).
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
	RETURN orb_from_vectors(o["r"], o["v"] + basis_transform(basis_mvr(), n, True), o["body"], t).
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
	RETURN ASINE(SIN(m+o["argp"]) * COS(90-o["inc"])).
}

// Returns expected anomaly value for a particular latitude.
FUNCTION orb_anomaly_at_latitude {
	PARAMETER lat.
	PARAMETER o IS obt.
	PARAMETER want IS KA_TRUE.  // Desired return anomaly type.
	PARAMETER alt IS FALSE.  // Return other alternate anomaly value.
	SET o TO orb_from_orbit(o).
	IF alt {
		RETURN orb_convert_anomaly(-ASINE(SIN(lat)/COS(90-o["inc"])) + 180 - o["argp"], o["ecc"], KA_TRUE, want).
	}
	RETURN orb_convert_anomaly(ASINE(SIN(lat)/COS(90-o["inc"])) - o["argp"], o["ecc"], KA_TRUE, want).
}
