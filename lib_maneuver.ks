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
	LOCAL vel IS o["v"].
	LOCAL b IS basis_une(o).
	LOCAL hdg IS heading_for_inclination(inc, ARCSIN(o["r"]:y/o["r"]:mag)).
	LOCAL hvel IS VXCL(b[KB_UP], vel).	// actualHorizontalVelocity.
	LOCAL e IS b[KB_EAST]*hvel:mag*sin(hdg). // New eastComponent
	LOCAL n IS b[KB_NORTH]*hvel:mag*cos(hdg).	// New North component
	IF (n*hvel<0)<>(Clamp180(inc)<0) { SET n TO -n. }
	RETURN vector_to_node(basis_transform(basis_mvr(o), e+n-hvel), ToSeconds(t)).
}

// Change inclination, efficiently.  Tries multiple options.  Returns a list of nodes to execute.
FUNCTION mvr_inclination_ex {
	PARAMETER t.  // Earliest maneuver time.
	PARAMETER maxalt.  // Maximum allowed alt of temporary apoapsis change.
	PARAMETER inc. // Target inclination.
	PARAMETER o IS ship.  // Any orbital, Orbit or Orb.
	LOCAL o IS orb_from_orbit(o).
	LOCAL tnode IS orb_next_anomaly(IIF(o["argp"]<180,180,0)-o["argp"],o,t,KA_TRUE).
	LOCAL candidates IS LIST().
	candidates:add(LIST(mvr_inclination(tnode,inc,o))).
	
	IF inc<>0 {
		LOCAL thigh IS ToSeconds(orb_next_anomaly(180,o,t,KA_TRUE)).
		LOCAL tlow IS ToSeconds(tnode).
		LOCAL sininc IS ABS(SIN(inc)).
		IF ABS(SIN(orb_latitude_at_anomaly(thigh))) > sininc {
			// AP is too high of latitude.  Figure out the anomaly of the nearest location at correct latitude.
			
			IF 90 < o["argp"] AND o["argp"] <= 270 {
				
				// tnode is descending, so we want northern latitude (positive inclination).
				
			
			
				
			LOCAL a1 IS orb_anomaly_at_latitude(
			
		IF ABS(orb_latitude_at_anomaly(thigh)) > ABS(inc)
		
		LOCAL testo IS orb_at_time(o,thigh).
		PRINT sininc.
		PRINT ABS(testo["r"]:y/testo["r"]:mag).
		IF sininc < ABS(testo["r"]:y/testo["r"]:mag) {
			// AP is at too high of a latitude, binary search for something at appropriate latitude.
			UNTIL ABS(thigh-tlow) < 1 {
				PRINT "Search range is " + tlow + " to " + thigh.
				// Find the lowest orbit at a latitude no greater than the desired inclination.
				LOCAL guess IS (thigh+tlow)/2.
				LOCAL testo IS orb_at_time(o,guess).
				IF sininc < ABS(testo["r"]:y/testo["r"]:mag) {
					// Too high of a latitude, go to the lower half of the search space.
					SET thigh TO guess.
				} ELSE {
					SET tlow TO guess.
				}
			}
		}
		candidates:add(LIST(mvr_inclination(thigh,inc,o))).
	}
	RETURN candidates.
}

LOCAL o IS orb_from_orbit().
LOCAL t IS TIME.
LOCAL tlan IS ToSeconds(orb_next_anomaly(-o["argp"],o,t).
LOCAL tldn IS ToSeconds(orb_next_anomaly(180-o["argp"],o,t).

