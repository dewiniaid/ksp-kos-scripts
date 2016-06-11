RUN ONCE lib_orbit.
RUN ONCE lib_string.
CLEARSCREEN.

LOCAL f_time IS STR_FORMATTER("{!t}     ").
LOCAL f_orbit IS STR_FORMATTER("Orbit: e={:6.4}   M={:-09.4}   v={:-09.4}  ").
LOCAL f_result IS STR_FORMATTER("Origin: {}:  M={:-09.4}   v={:-09.4}   E={:-09.4}").
LOCAL conv IS orb_convert_anomaly@.

LOCAL firstrun IS true.
ON ROUND(TIME:Seconds,1) {
	LOCAL t IS TIME.
	LOCAL e IS obt:eccentricity.
	LOCAL v IS obt:trueanomaly.
	LOCAL m IS obt:meananomalyatepoch.
	LOCAL lines IS LIST().
	lines:ADD(f_time(LIST(TIME))).
	lines:ADD(f_orbit(LIST(obt:eccentricity, obt:meananomalyatepoch, obt:trueanomaly))).
	
	// Test results using True as the base.
	LOCAL ma IS conv(v, e, KA_TRUE, KA_MEAN).
	LOCAL ea IS conv(v, e, KA_TRUE, KA_ECC).
	lines:ADD(f_result(LIST("v", ma, v, ea))).
	
	// Test results using Ecc as the base.
	lines:ADD(f_result(LIST("E", conv(ea, e, KA_ECC, KA_MEAN), conv(ea, e, KA_ECC, KA_TRUE), ea))).
	
	// Test results using Mean as the base.
	lines:ADD(f_result(LIST("M", ma, conv(ma, e, KA_MEAN, KA_TRUE), conv(ma, e, KA_MEAN, KA_ECC)))).
	lines:ADD("*** Press any movement key to end script ***").
	lines:ADD("------------------------------  ").
	
	FOR ix IN RANGE(lines:length) {
		IF firstrun { PRINT " ". }
		PRINT lines[ix] AT(0,ix).
	}
	SET firstrun TO false.
	PRESERVE.
}

WAIT UNTIL ship:control:pilotyaw<>0 OR ship:control:pilotpitch<>0 OR ship:control:pilotroll<>0.
