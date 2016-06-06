RUN ONCE lib_orbit.
RUN ONCE lib_util.
RUN ONCE lib_string.
LOCAL fmt IS str_format@.

PRINT time.
LOCAL t IS TIME.
LOCAL o IS orb_from_orbit().
LOCAL test_sep IS str_repeat("-", 20).
LOCAL group_sep IS str_repeat("=", 40).

{
	PRINT "Testing orb_next_anomaly...".
	LOCAL _types IS LEXICON(KA_MEAN, "Mean", KA_ECC, "Eccentric", KA_TRUE, "True").
	FUNCTION TEST {
		PARAMETER text.
		PARAMETER m.
		PRINT test_sep.
		PRINT FMT("Test: {} (m={:.2}deg)", LIST(text, m)).
		FOR k IN _types:keys {
			PRINT FMT("{:.<30} {}", LIST(
				FMT("[{}] {} anomaly in", LIST(k, _types[k])),
				(orb_next_anomaly(m,o,t,k) - t):clock
			)).
		}
	}
	
	TEST("Periapsis (should be correct for all)", 0).
	TEST("Apoapsis (should be correct for all)", 180).
	TEST("LAN (should be correct for True)", -o["argp"]).
	TEST("LDN (should be correct for True)", 180-o["argp"]).
}
PRINT group_sep.
{
	PRINT "Testing orbit predictions...".
	LOCAL timedelta IS 1.
	FUNCTION TEST {
		PARAMETER desc.
		PRINT test_sep.
		PRINT FMT("Test: {}", desc).
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
	PRINT "Testing anomaly<=>radius conversions (using True Anomaly values)...".
	FUNCTION TEST {
		PARAMETER desc.
		PARAMETER r.
		PARAMETER m.
		SET m TO clamp360(m).
		LOCAL testr IS orb_radius_for_anomaly(m,o,KA_TRUE).
		PRINT test_sep.
		PRINT FMT("Test: {} (anomaly: {:6.2})", LIST(desc, m)).
		IF r<>0 { PRINT FMT("{:.<20} {:13.2}", LIST("Actual radius", r)). }
		PRINT FMT("{:.<20} {:13.2}", LIST("Calculated", testr)).
		IF r<>0 { PRINT FMT("{:.<20} {:13.2}", LIST("   Delta (should be minimal)", IIF(r=0,"N/A", testr-r))). }
		LOCAL testm IS Clamp360(orb_anomaly_at_radius(testr,o,KA_TRUE)).
		PRINT FMT("Target anomaly: {:.2}; reported: {:.2} (or {:.2}); delta: {:.2} (or {:.2})", LIST(m, testm, 360-testm, testm-m, 360-testm-m)).
	}
	TEST("Periapsis", o["pe"], 0).
	TEST("Apoapsis", o["ap"], 180).
	TEST("LAN", 0, -o["argp"]).
	TEST("LDN", 0, 180-o["argp"]).
	TEST("North", 0, 90-o["argp"]).
	TEST("South", 0, 270-o["argp"]).
}
PRINT group_sep.
	PRINT "Testing anomaly<=>latitude conversions (using True Anomaly values)...".
	FUNCTION TEST {
		PARAMETER desc.
		PARAMETER lat.
		PARAMETER m.
		SET m TO clamp360(m).
		LOCAL olat IS orb_latitude_for_anomaly(m,o,KA_TRUE).
		PRINT FMT("Test: {} (anomaly: {:6.2})", LIST(desc, m)).
		PRINT FMT("Target latitude: {:.2}; reported: {:.2}; delta: {:.2}", LIST(lat, olat, olat-lat)).
		LOCAL m1 IS orb_anomaly_at_latitude(lat,o,KA_TRUE,false).
		LOCAL m2 IS orb_anomaly_at_latitude(lat,o,KA_TRUE,true).
		PRINT FMT("Target anomaly: {:.2}; reported: {:.2} (or {:.2}); delta: {:.2} (or {:.2})", LIST(m, m1, m2, m1-m, m2-m)).
	}
	TEST("LAN", 0, -o["argp"]).
	TEST("LDN", 0, 180-o["argp"]).
	TEST("North -- alternate should equal primary", o["inc"], 90-o["argp"]).
	TEST("South -- alternate should equal primary", -o["inc"], 270-o["argp"]).
	
	