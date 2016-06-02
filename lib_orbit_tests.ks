RUN ONCE lib_orbit.
RUN ONCE lib_util.

PRINT time.
LOCAL t IS TIME.
LOCAL o IS orb_from_orbit().
{
	PRINT "Testing orb_next_anomaly...".
	FUNCTION TEST {
		PARAMETER text.
		PARAMETER m.
		PRINT "------".
		PRINT "Running test '" + text + "' (anomaly: " + m + ")'".
		PRINT "Mean in " + (orb_next_anomaly(m,o,t, KA_MEAN) - t):clock.
		PRINT "Ecc in " + (orb_next_anomaly(m,o,t, KA_ECC) - t):clock.
		PRINT "True in " + (orb_next_anomaly(m,o,t, KA_TRUE) - t):clock.
	}
	
	TEST("Periapsis (should be correct for all)", 0).
	TEST("Apoapsis (should be correct for all)", 180).
	TEST("LAN (should be correct for True)", -o["argp"]).
	TEST("LDN (should be correct for True)", 180-o["argp"]).
	PRINT "======".
}
{
	LOCAL timedelta IS 30.
	FUNCTION TEST {
		PRINT "------".
		PRINT "Actual location:    " + actual_r.
		PRINT "Projected location: " + o["r"].
		PRINT "...delta (mag):     " + (o["r"]-actual_r) + " (" + (o["r"]-actual_r):mag + ")".
		PRINT "Actual velocity:    " + actual_v.
		PRINT "Projected velocity: " + o["v"].
		PRINT "...delta (mag):     " + (o["v"]-actual_v) + " (" + (o["v"]-actual_v):mag + ")".
		PRINT "Projected anomaly values:".
		PRINT "..." + o["mna"] + " mean, " + o["eccanomaly"] + " ecc, " + o["trueanomaly"] + " true".
	}
	WAIT 0.
	LOCAL o IS orb_at_time(o,t+timedelta).
	LOCAL actual_r IS RELPOSITIONAT(ship, ToSeconds(t+timedelta)).
	LOCAL actual_v IS VELOCITYAT(ship, t+timedelta):orbit.
	TEST().
	WAIT 0.
	LOCAL o IS orb_set_time(orb_from_vectors(RELPOSITION(obt), obt:velocity:orbit),t+timedelta).
	LOCAL actual_r IS RELPOSITIONAT(ship, ToSeconds(t+timedelta)).
	LOCAL actual_v IS VELOCITYAT(ship, t+timedelta):orbit.
	TEST().
}