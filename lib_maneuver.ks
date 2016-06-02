@LAZYGLOBAL OFF.
RUN ONCE lib_util.
RUN ONCE lib_basis.
RUN ONCE lib_orbit.

// Change semimajor axis at time.
FUNCTION mvr_change_sma {
	PARAMETER t.  // Maneuver time.
	PARAMETER a.  // New semimajor axis.
	PARAMETER o IS ship.  // Any Orbital, Orbit, or Orb.
	SET o TO orb_at_time(o,t).
	IF o["rmag"] > a*2 { 
		PRINT "*** WARNING: attempted to plot a maneuver where target_sma < height.".
		RETURN.
	}
	RETURN NODE(t:seconds, 0, 0, SQRT(o["mu"] * (2/o["rmag"] - 1/a)) - SQRT(o["mu"] * (2/o["rmag"] - 1/o["sma"]))).
}

// Circularize at altitude.
FUNCTION mvr_circularize_at_alt {
	PARAMETER t.  // Earliest maneuver time.
	PARAMETER r.  // Altitude.
	PARAMETER o IS ship.  // Any Orbital, Orbit, or Orb.
	SET o TO orb_at_time(o,t).
	IF r < o["pe"] OR r > o["ap"] {
		PRINT "*** WARNING: attempted to plot a maneuver where r < pe or r > ap.".
		RETURN.
	}
	LOCAL m IS orb_anomaly_at_radius(r,o,KA_MEAN).
	LOCAL t IS MIN(
		orb_next_anomaly(m,o,t,KA_MEAN):seconds,
		orb_next_anomaly(360-m,o,t,KA_MEAN):seconds
	).
	orb_set_time(o,t).
	LOCAL vel IS (VXCL(o["r"], o["v"]):normalized * SQRT(o["mu"]/r)).
	RETURN vector_to_node(basis_transform(basis_mvr(o), vel-o["v"]), t).
}
	

FUNCTION heading_for_inclination {
	PARAMETER inc.	// Target inclination.
	PARAMETER lat.	// Latitude; arcsin(pos:y/pos:mag)
	LOCAL costarget IS 2.
	IF Clamp360(lat)<>90 { SET costarget TO COS(inc)/COS(lat). }
	IF ABS(costarget) > 1 {
		// Impossible inclination at this latitude.
		IF abs(Clamp180(inc)) < 90 {
			RETURN 90.
		}
		RETURN 270.
	}
	RETURN Clamp360(90 - ACOS(costarget,inc)).
}

// Changes inclination.
FUNCTION mvr_inclination {
	PARAMETER t.  // Maneuver time.
	PARAMETER inc.  // Target inclination
	PARAMETER o IS ship.  // Any Orbital, Orbit, or Orb.
	SET o TO orb_at_time(o,t).
	PRINT o["r"].
	LOCAL vel IS o["v"].
	PRINT (ToTime(t)-Time):Clock.

	LOCAL b IS basis_une(o).
	LOCAL hdg IS heading_for_inclination(inc, ARCSIN(o["r"]:y/o["r"]:mag)).
	
	PRINT hdg.
	
	LOCAL hvel IS VXCL(b[KB_UP], vel).	// actualHorizontalVelocity.
	LOCAL e IS b[KB_EAST]*hvel:mag*sin(hdg). // New eastComponent
	LOCAL n IS b[KB_NORTH]*hvel:mag*cos(hdg).	// New North component
	IF (n*hvel<0)<>(Clamp180(inc)<0) { SET n TO -n. }
	PRINT e+n.
	PRINT hvel.
	PRINT e+n-hvel.
	PRINT (e+n)-hvel.
	RETURN vector_to_node(basis_transform(basis_mvr(o), e+n-hvel), ToSeconds(t)).
	
	
	LOCAL lvel IS basis_transform(b, vel).
	LOCAL hvel IS V(0,lvel:y,lvel:z).
	LOCAL tvel IS V(lvel:x,hvel:mag*cos(hdg),hvel:mag*sin(hdg)).
	PRINT V(0,tvel:y,tvel:z):mag.
	IF (vel:y<0)=(Clamp180(inc)>0) {
		SET tvel:y TO -tvel:y.
	}
	LOCAL mvr IS basis_transform(basis_mvr(o), basis_transform(b, tvel-lvel, true)).
	// RETURN NODE(t:seconds, mvr:x, mvr:y, mvr:z).
	
	LOCAL b IS basis_mvr(o).
	LOCAL hvel IS VXCL(b[0], vel).
	LOCAL mvr IS basis_transform(b, hvel).
	SET mvr TO V(0, mvr:mag*cos(hdg), mvr:mag*sin(hdg))-mvr.
	RETURN NODE(t:seconds, mvr:x, mvr:y, mvr:z).
}	

// LOCAL n IS mvr_circularize_at_alt(time, 500*K_KM+body:radius).
//LOCAL predicted IS orb_predict(obt, n).
//PRINT predicted.
//ADD n.
PRINT time.
LOCAL o IS orb_from_orbit().
RUN_TEST("LAN-", -o["argp"]).
PRINT obt:argumentofperiapsis.
PRINT o["argp"].
LOCAL m IS -o["argp"].
LOCAL result IS orb_next_anomaly(m,o,time,KA_TRUE).
PRINT (result-time):Clock.
ADD mvr_inclination(orb_next_anomaly(-obt:argumentofperiapsis,obt,time,KA_TRUE),0).
