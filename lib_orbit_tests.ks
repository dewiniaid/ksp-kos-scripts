CLEARSCREEN.
RUN ONCE lib_orbit.
RUN ONCE lib_util.
RUN ONCE lib_string.
LOCAL fmt IS str_format@.

LOCAL t IS TIME.
LOCAL o IS orb_from_orbit(ship, t).

LOCAL test_sep IS str_repeat("-", 20).
LOCAL group_sep IS str_repeat("=", 40).
PRINT FMT("Orbital period: {0:.2}  ({0!d})  arate: {1:.2}  ({1!d})", LIST(ToSeconds(o["period"]), o["arate"])).
PRINT group_sep.
LOCAL atype IS LEXICON(KA_TRUE, "v", KA_ECC, "E", KA_MEAN, "M").
	
{
	PRINT "Testing orb_next_anomaly predictions...".
	FUNCTION TEST {
		PARAMETER text.
		PARAMETER m.
		PARAMETER k IS KA_TRUE.
		LOCAL a IS orb_next_anomaly(m,o,t,k).
		IF IsFalse(a) { SET a TO "NO SOLUTION". } ELSE { SET a TO a-t. }
		PRINT FMT("Next {:.<15} {}={:6.2} in {!d}", LIST(text, atype[k], m, a)).
	}
	
	TEST("Periapsis", 0).
	TEST("Apoapsis", 180).
	TEST("LAN", -o["argp"]).
	TEST("LDN", 180-o["argp"]).
	TEST("Soon", o["mna"]+(1E-05), KA_MEAN).
	TEST("Recent", o["mna"]-(1E-05), KA_MEAN).
	TEST("+1deg", o["mna"]+1, KA_MEAN).
	TEST("-1deg", o["mna"]-1, KA_MEAN).
}
PRINT group_sep.
{
	PRINT "Testing orbit predictions...".
	LOCAL timedelta IS 1.
	FUNCTION TEST {
		PARAMETER desc.
		PRINT test_sep.
		PRINT FMT("Test: {}", LIST(desc)).
		PRINT FMT("{:.<20} {:13.2}", LIST("Actual location", actual_r)).
		PRINT FMT("{:.<20} {:13.2}", LIST("Projected location", o["r"])).
		PRINT FMT("{:.<20} {:13.2} (mag {1!m:.2})", LIST("   Delta", o["r"]-actual_r)).
		PRINT FMT("{:.<20} {:13.2}", LIST("Actual velocity", actual_r)).
		PRINT FMT("{:.<20} {:13.2}", LIST("Projected velocity", o["v"])).
		PRINT FMT("{:.<20} {:13.2} (mag {1!m:.2})", LIST("   Delta", o["v"]-actual_v)).
		PRINT FMT("Projected anomaly values: {:0.2} mean; {:0.2} ecc; {:0.2} true", LIST(o["mna"], o["eccanomaly"], o["trueanomaly"])).
	}
	WAIT 0.
	LOCAL t IS time+timedelta.
	LOCAL o IS orb_at_time(o,t).
	LOCAL actual_r IS RELPOSITIONAT(ship, ToSeconds(t)).
	LOCAL actual_v IS VELOCITYAT(ship, t):orbit.
	TEST("Timeshifted orbit").
	WAIT 0.
	LOCAL t IS time+timedelta.
	LOCAL o IS orb_set_time(orb_from_vectors(RELPOSITION(obt), obt:velocity:orbit),t).
	LOCAL actual_r IS RELPOSITIONAT(ship, ToSeconds(t)).
	LOCAL actual_v IS VELOCITYAT(ship, t):orbit.
	TEST("Orbit constructed from vectors").
}
PRINT group_sep.
{	
	PRINT "Testing anomaly<=>radius conversions...".
	PRINT "[Descript]   [__Anom]   [______ActualRadius]   [__CalculatedRadius]   [_____________Delta]   TgtAnom   [Calc1]   [Calc2]   _Delta1   _Delta2".
	LOCAL fmt_withradius IS str_formatter("{0:.<10} _ {10}={1:6.2} _ {2:20.2} _ {3:20.2} _ {4:20.2} _ {5:7.3} _ {6:7.3} _ {7:+6.3} _ {8:+7.2} _ {9:+7.2}").
	LOCAL fmt_noradius   IS str_formatter("{0:.<10} _ {10}={1:6.2} _                -n/a- _ {3:20.2} _                -n/a- _ {5:7.3} _ {6:7.3} _ {7:+6.3} _ {8:+7.2} _ {9:+7.2}").
	
	FUNCTION TEST {
		PARAMETER desc.
		PARAMETER r.
		PARAMETER m.
		PARAMETER k IS KA_TRUE.
		LOCAL testr IS orb_radius_atanomaly(m,o,k).
		LOCAL testm IS (orb_anomaly_at_radius(testr,o,KA_TRUE)).
		PRINT IIF(r<>0,fmt_withradius@,fmt_noradius@)(LIST(desc, m, r, testr, r-testr, m, testm, 360-testm, m-testm, m-(360-testm),atype[k])).
	}
	TEST("Periapsis", o["pe"], 0).
	TEST("Apoapsis", o["ap"], 180).
	TEST("LAN", 0, Clamp360(-o["argp"])).
	TEST("LDN", 0, Clamp360(180-o["argp"])).
	TEST("North", 0, Clamp360(90-o["argp"])).
	TEST("South", 0, Clamp360(270-o["argp"])).
}
PRINT group_sep.
{
	PRINT "Testing anomaly<=>latitude conversions (using True Anomaly values)...".
	PRINT "[Descript]   [Anom]   [ActualLat]   [CalcLat]   [LatAnom1] (delta1)   [LatAnom2] (delta)".
	LOCAL fmt_lat IS str_formatter("{:.<10} _ {:6.2} _ {:11.2} _ {:9.2} _ {:10.2} ({:+6.1}) _ {:10.2} ({:+6.1})").
	FUNCTION TEST {
		PARAMETER desc.
		PARAMETER lat.
		PARAMETER m.
		SET m TO (m).
		LOCAL olat IS orb_latitude_atanomaly(m,o,KA_TRUE).
		LOCAL m1 IS orb_anomaly_at_latitude(lat,o,KA_TRUE,false).
		LOCAL m2 IS orb_anomaly_at_latitude(lat,o,KA_TRUE,true).
		PRINT fmt_lat(LIST(desc, m, lat, olat, m1, m-m1, m2, m-m2)).
		
		//PRINT FMT("Test: {} (anomaly: {:6.2})", LIST(desc, m)).
		//PRINT FMT("Target latitude: {:.2}; reported: {:.2}; delta: {:.2}", LIST(lat, olat, olat-lat)).
		//PRINT FMT("Target anomaly: {:.2}; reported: {:.2} (or {:.2}); delta: {:.2} (or {:.2})", LIST(m, m1, m2, m1-m, m2-m)).
	}
	TEST("LAN", 0, -o["argp"]).
	TEST("LDN", 0, 180-o["argp"]).
	TEST("North", o["inc"], 90-o["argp"]).
	TEST("South", -o["inc"], 270-o["argp"]).
}

