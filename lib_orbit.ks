@LAZYGLOBAL OFF.
RUN ONCE lib_util.
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
// d mu:    Shortcut to body:mu.
// d slr:   Semi-latus rectum. (l)
// d smna:  Semi-minor axis. (b)

// TEMPORAL ELEMENTS (time-based, relative to defined epoch).
// e eccentricanomaly: Eccentric Anomaly.
// t trueanomaly: True Anomaly.
// r rmag:  Radius.  (More accurate than r:mag).
// r r:     Position vector relative to body. (SOI-RAW rather than SHIP-RAW.  Sort of.).
// v vmag:  Orbital speed  (More accurate than v:mag).
// v v:     Velocity vector.


FUNCTION orb_from_orbit {
	PARAMETER o IS obt.
	PARAMETER t IS TIME.
	IF t:typename() <> "Timespan" { SET t TO TIME(t). }
	IF o:istype("orbitable") { SET o TO ORBITAT(o, t:seconds). }
	LOCAL r IS obt:position - obt:body:position.
	LOCAL v IS obt:velocity:orbit.
	// Create most of the initial orbit parameters, and then change epoch to our reference time.
	LOCAL orb IS orb_update(LEXICON(
		"body", obt:body,
		"ecc", obt:eccentricity,
		"sma", obt:semimajoraxis,
		"inc", obt:inclination,
		"lan", obt:lan,
		"argp", obt:argumentofperiapsis,
		"mna", obt:meananomalyatepoch,
		"epoch", time,
		"period", obt:period,
		"ap", obt:apoapsis,
		"pe", obt:periapsis,
		"mu", obt:body:mu,
		"trueanomaly", obt:trueanomaly,
		"rmag", r:mag,
		"r", r,
		"vmag", v:mag,
		"v", v
	), "d").
	IF t=TIME {
		orb_update(orb, "e").
	} ELSE {
		orb_set_time(orb, t).
	}
	RETURN orb.
}


FUNCTION eccentric_anomaly_from_mean {
	PARAMETER m.   // Mean anomaly
	PARAMETER ecc. // Eccentricity.
	PARAMETER attempts IS 100.
	SET m TO MOD(m,360).
	IF m=0 OR m=180 OR ecc=0 { RETURN m. }
	IF m>180 { RETURN 360-eccentric_anomaly_from_mean(360-m, ecc). }
	LOCAL lower IS m.
	LOCAL upper IS 180.
	
	IF DEFINED(eccentric_anomaly_table) {
		// Faster calculations if we have the anomaly table loaded.
		LOCAL t IS eccentric_anomaly_table.
		LOCAL r IS FLOOR(ecc*T:length).
		LOCAL c IS FLOOR(m/180 * T[0]:length).
		SET upper TO t[r][c].
		IF r>0 AND c>0 { SET lower TO t[r-1][c-1]. }
	}
	LOCAL guess IS (lower+upper)/2.
	SET m TO m/K_DEGREES.
	
	FOR attempt IN RANGE(attempts) {
		SET guess TO (lower+upper)/2.
		LOCAL err IS (guess/K_DEGREES - ecc*SIN(guess))-m.
		IF ABS(err) < 1e-15 { RETURN guess. }
		IF err > 0 {
			SET upper TO guess.
		} ELSE {
			SET lower TO guess.
		}
	}
	RETURN guess.
}


// (Re)calculates derived and temporal elements from the orbit.
FUNCTION orb_update {
	PARAMETER o.
	PARAMETER what IS "etrv".  // Determines which parameters to recalculate.  By default, only temporal parameters.
	
	SET o["mu"] TO o["body"]:mu.
	IF what:contains("o") {
		SET o["pe"] TO (1-o["ecc"])*o["sma"].
		SET o["ap"] TO (1+o["ecc"])*o["sma"].
		SET o["period"] TO 2*constant():pi*SQRT(o["sma"]^3 / o["body"]:mu).
	}
	IF what:contains("d") {
		SET o["smna"] TO ABS(o["sma"]/SQRT(1 - o["ecc"]^2)).
		SET o["slr"] TO o["smna"]^2/o["sma"].
	}
	IF what:contains("e") {  // Eccentric anomaly
		SET o["eccanomaly"] TO eccentric_anomaly_from_mean(o["mna"], o["ecc"]).
	}
	IF what:contains("t") {  // True anomaly.
		SET o["trueanomaly"] TO ACOS((COS(o["eccanomaly"])-o["ecc"])/(1-o["ecc"]*COS(o["eccanomaly"])), 180-o["eccanomaly"]).
		// IF o["eccanomaly"]>180 { SET o["trueanomaly"] TO 360-o["trueanomaly"]. }
	}
	IF what:contains("r") {  // Position vector.
		SET o["rmag"] TO o["sma"]*(1-o["ecc"]^2)/(1+o["ecc"]*COS(o["trueanomaly"])).
		SET o["r"] TO (
			V(0,0,o["sma"]*(1-o["ecc"]^2)/(1+o["ecc"]*COS(o["trueanomaly"])))
			+ -R((o["trueanomaly"] + o["argp"])*o["inc"],0,0)
			+ -R(0,o["trueanomaly"]+o["argp"]+o["lan"]-solarprimevector:direction:yaw,0)
		).
	}
	IF what:contains("v") {  // Velocity vector.
		SET o["vmag"] TO SQRT(o["mu"]*(2/o["rmag"]-1/o["sma"])).
		// Can't directly calculate velocity; so compare positions in a 1-second window centered on our epoch.
		// Make sure we don't ask those calculations to include a velocity.
		LOCAL prev IS orb_set_time(o:copy(), o["epoch"]-0.5, "etr").
		LOCAL next IS orb_set_time(o:copy(), o["epoch"]+0.5, "etr").
		SET o["v"] TO next["r"]-prev["r"].
	}
	RETURN o.
}


// Changes the epoch of an orbit, updating MNA and other parameters accordingly.
FUNCTION orb_set_time {
	PARAMETER o.
	PARAMETER t IS TIME.
	PARAMETER calc IS "etrv".  // What to recalculate after epoch change.
	IF t:typename() <> "Timespan" { SET t TO TIME(t). }
	IF t=o["epoch"] { RETURN o. }
	LOCAL p IS orbit_get_period(o).
	SET o["mna"] TO MOD((t-o["epoch"]):seconds, o["period"])*360/o["period"].
	SET o["epoch"] TO t.
	RETURN orb_update(o, calc).
}

FUNCTION orb_from_vectors {
	PARAMETER r IS obt:position - body:position.
	PARAMETER v IS obt:velocity:orbit.
	PARAMETER b IS body.
	PARAMETER t IS TIME.
	
	LOCAL h IS VCRS(r, v).	// Angular momentum.
	LOCAL mu IS b:mu.
	LOCAL evec IS ((v:mag^2 - mu/r:mag) * r - (r*v)*v).	// Eccentricity.
	LOCAL ecc IS evec:mag / mu.	// Eccentricity.
	LOCAL n IS v(h:z, 0, -h:x).  // Node vector.
	LOCAL argp IS ACOS((evec*n)/(evec:mag*n:mag), evec:y).
	LOCAL mult IS IIF(r*v < 0, -1, 1).
	LOCAL ta IS ACOS(evec*r/(evec:mag*r:mag),mult).  // True anomaly
	LOCAL ea IS ACOS((ecc+COS(ta))/(1+ecc*COS(ta)),mult).  // Ecc anomaly
	
	// Orbital energy.
	// LOCAL e IS (v:mag^2)/2 - (mu/r:mag).	// Energy.
	// LOCAL a IS -mu/(2*((v:mag^2)/2 - (mu/r:mag))).	// Semi-major axis.
	// LOCAL p IS a*(1-ecc^2).	// Parameter, semi-latus rectum
	RETURN orb_update(LEXICON(
		"body", body,
		"ecc", ecc,
		"sma", -mu/(2*((v:mag^2)/2 - (mu/r:mag))),
		"inc", 180 - arccos(h:y/h:mag),  // Inclination.  0=polar, 90=equatorial.
		"lan", ACOS(n:x/n:mag, n:z) - ACOS(solarprimevector:x, solarprimevector:z),
		"argp", ACOS((evec*n)/(evec:mag*n:mag), evec:y),
		"mna", Clamp360(mult * K_DEGREES * (ea/K_DEGREES - ecc*SIN(ea))),
		"epoch", t,
		"trueanomaly", ta,
		"eccanomaly", ea,
		"rmag", r:mag,
		"r", r,
		"vmag", v:mag,
		"v", v
	), "od").
}
