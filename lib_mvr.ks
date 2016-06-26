@LAZYGLOBAL OFF.
RUN ONCE lib_util.
RUN ONCE lib_basis.
RUN ONCE lib_obt.
RUN ONCE lib_string.
RUN ONCE lib_iter.
RUN ONCE lib_ship.

// Maneuver planning library.

// Returns true if a nextnode exists.
FUNCTION node_has_nextnode {
	//LOCAL sentinel IS NODE(TIME:Seconds+2^32,42,1337,359).
	//ADD sentinel.
	//LOCAL r IS NEXTNODE<>sentinel.
	//REMOVE sentinel.
	//RETURN r.
	RETURN HASNODE.
}

// Clears all maneuver nodes.
FUNCTION node_clear {
	//LOCAL sentinel IS NODE(TIME:Seconds+2^32,42,1337,359).
	//ADD sentinel.
	//UNTIL NEXTNODE=sentinel { REMOVE NEXTNODE. }
	//REMOVE sentinel.
	UNTIL NOT HASNODE { REMOVE NEXTNODE. }
}

// Returns total dV of the node (or list of nodes).
FUNCTION node_dv {
	PARAMETER nd.
	IF nd:istype("List") {
		LOCAL dv IS 0.
		FOR item IN nd { SET dv TO dv + SQRT(item:radialout^2+item:normal^2+item:prograde^2). }
		RETURN dv.
	}
	RETURN SQRT(nd:radialout^2+nd:normal^2+nd:prograde^2).
}

// Return the lower DV of the two passed node values.
FUNCTION node_choose {
	PARAMETER a.
	PARAMETER b.
	RETURN IIF(node_dv(a) < node_dv(b), a, b).
}

// Copy the list of nodes.
FUNCTION node_copyall {
	PARAMETER src.
	LOCAL dst IS LIST().
	FOR nd IN src {
		dst:add(node_copy(nd)).
	}
	RETURN dst.
}


		
// Change semimajor axis at time.
FUNCTION mvr_change_sma {
	PARAMETER t.  // Maneuver time.
	PARAMETER a.  // New semimajor axis.
	PARAMETER ship IS ship.
	PARAMETER nd IS FALSE.  // Node to update in place.
	LOCAL o IS ORBITAT(ship, ToSeconds(t)).
	LOCAL rmag IS RELPOSITIONAT(ship,ToSeconds(t)):mag.
	IF a < rmag/2 {
		PRINT STR_FORMAT("*** WARNING: cannot reduce semi-major axis below half the altitude of the burn. ({} < {})", LIST(a, rmag/2)).
		RETURN FALSE.
	}
	RETURN vector_to_node(V(0, 0, SQRT(o:body:mu*(2/rmag - 1/a)) - SQRT(o:body:mu * (2/rmag - 1/o:semimajoraxis))), t, nd).
}

// Circularize at radius.
FUNCTION mvr_circularize_at_radius {
	PARAMETER t.  // Earliest maneuver time.
	PARAMETER r.  // Altitude.
	PARAMETER ship IS ship.
	PARAMETER nd IS FALSE.  // Node to update in place.
	SET t TO ToSeconds(t).
	SET o TO ORBITAT(ship, ToSeconds(t)).
	IF NOT BETWEEN(o:periapsis+body:radius, r, o:apoapsis+body:radius) {
		PRINT "*** WARNING: attempted to plot a maneuver where r < pe or r > ap.".
		RETURN FALSE.
	}
	LOCAL m IS obt_anomaly_at_radius(r,o,KA_MEAN).
	
	IF o:eccentricity<1 {SET t TO ToSeconds(obt_earliest_anomaly(LIST(m,360-m),o,t,KA_MEAN)). }
	ELSE { SET t TO ToSeconds(obt_next_anomaly(m,o,t,KA_MEAN)). }
	LOCAL opos IS RELPOSITIONAT(ship, t).
	LOCAL ovel IS VELOCITYAT(ship, t):orbit.
	LOCAL vel IS VXCL(opos, ovel):normalized * SQRT(o:body:mu/r).
	FUNCTION _rebuild {
		PARAMETER t.
		RETURN mvr_circularize_at_radius(MAX(TIME:seconds, ToSeconds(t)), r, ship).
	}
		
	RETURN vector_to_node(basis_transform(basis_mvr(opos,ovel), vel-ovel), t, nd).
}

FUNCTION _dv_for_apsis {
	PARAMETER t.
	PARAMETER z.
	PARAMETER v.
	PARAMETER mu.
	
	RETURN SQRT((2*mu*z*(z-r:mag))/(r:mag*z^2-r:mag^3*(VCRS(r,v):mag/(r:mag*v:mag))^2)) - v:mag.
}
	
// Set apsis at time.
FUNCTION mvr_set_apsis {
	PARAMETER dir.
	PARAMETER t.  // Earliest maneuver time.
	PARAMETER burnheight.  // Height to perform burn at.  If FALSE, uses exact time instead.
	PARAMETER z.  // Target apoapsis
	PARAMETER ship IS ship.
	PARAMETER nd IS FALSE.  // Node to update in place.
	LOCAL o IS ORBITAT(ship, ToSeconds(t)).
	IF NOT IsFalse(burnheight) {
		SET t TO obt_next_radius(burnheight, o, t).
	}
	LOCAL r IS RELPOSITIONAT(ship, t).
	PRINT STR_FORMAT("burnheight: {} -- rmag: {} -- z: {}", LIST(burnheight, r:mag, z)).
	IF r:mag>z AND dir>0 {
		PRINT str_format("*** WARNING: cannot plot a burn where the target apoapsis is below the burn height ({} <= {})", LIST(z, r:mag)).
		RETURN FALSE.
	} 
	IF r:mag<z AND dir<0 {
		PRINT str_format("*** WARNING: cannot plot a burn where the target periapsis is above the burn height ({} >= {})", LIST(z, r:mag)).
		RETURN FALSE.
	}
	IF r=z {
		// The normal method produces a singularity, so workaround this.
		IF dir>0 { // r is apoapsis.
			RETURN nd_change_sma(t, (r:mag+o:periapsis+o:body:radius)/2, ship, nd).
		} ELSE {
			RETURN nd_change_sma(t, (r:mag+o:apoapsis+o:body:radius)/2, ship, nd).
		}
	}
	LOCAL v IS VELOCITYAT(ship, t):orbit.
	LOCAL ycos IS VCRS(r,v):mag/(r:mag*v:mag).
	RETURN vector_to_node(V(0, 0, SQRT((2*body:mu*z*(z-r:mag))/(r:mag*z^2-r:mag^3*ycos^2))-v:mag), t, nd).
}
GLOBAL mvr_set_apoapsis IS mvr_set_apsis@:bind(1).
GLOBAL mvr_set_periapsis IS mvr_set_apsis@:bind(-1).
	

	
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
	PARAMETER ship IS ship.
	PARAMETER nd IS FALSE.  // Optional maneuver node to update in-place.
	SET t TO ToSeconds(t).
	LOCAL o IS ORBITAT(ship, ToSeconds(t)).
	LOCAL opos IS RELPOSITIONAT(ship, t).
	LOCAL ovel IS VELOCITYAT(ship, t):orbit.
	LOCAL b IS basis_une(opos, ovel).
	LOCAL hdg IS heading_for_inclination(inc, ARCSIN(opos:y/opos:mag)).
	LOCAL hvel IS VXCL(b[KB_UP], ovel).	// actualHorizontalVelocity.
	LOCAL e IS b[KB_EAST]*hvel:mag*sin(hdg). // New eastComponent
	LOCAL n IS b[KB_NORTH]*hvel:mag*cos(hdg).	// New North component
	IF (n*hvel<0)<>(Clamp180(inc)<0) { SET n TO -n. }
	RETURN vector_to_node(basis_transform(basis_mvr(opos,ovel), e+n-hvel), t, nd).
}

// Change inclination, efficiently.
FUNCTION mvr_inclination_ex {
	PARAMETER t.  // Earliest maneuver time.
	PARAMETER inc. // Target inclination.
	PARAMETER ship IS ship.
	PARAMETER nd IS FALSE.
	SET t TO ToSeconds(t).
	LOCAL o IS ORBITAT(ship, ToSeconds(t)).
	LOCAL argp IS o:argumentofperiapsis.
	
	// Come up with initial maneuver node candidates.
	// LAN/LDN
	LOCAL best IS mvr_inclination(obt_next_latitude(0, o, t, FALSE, 1), inc, ship).
	LOCAL m_high IS 180.
	LOCAL t_high IS FALSE.
	LOCAL m_ns IS -1.
	LOCAL t_ns IS FALSE.
	
	// At inclinations > 0, we can attempt alternate plans that may be more efficient.
	IF inc<>0 {
		LOCAL sininc IS ABS(SIN(inc)).
		// Find highest location within latitude band.  Start at apoapsis.
		// TODO: FIXME: Hyperbolic orbits.
		IF o:eccentricity<=1 { 
			SET t_high TO ToSeconds(obt_next_anomaly(180,o,t)).
		}
		IF IsFalse(t_high) OR ABS(SIN(obt_latitude_at_anomaly(m_high,o))) > sininc {
			SET m_high TO obt_anomalies_at_latitude(lat,o,want,TRUE,1).
			SET t_high TO obt_next_anomaly(m_high,o,t).
		}
		SET best TO node_choose(best, mvr_inclination(t_high,inc,ship)).
		IF ABS(SIN(o:inclination)) < sininc {
			// Sometimes it may be worthwhile to check the northernmost/southernmost points of the orbit.
			// (whichever is highest)
			SET m_ns TO Clamp360(IIF(BETWEEN(0, Clamp360(argp), 180), 90, 270) - argp).
			SET t_ns TO obt_next_anomaly(m_ns,o,t).
			SET best TO node_choose(best, mvr_inclination(t_ns,inc,ship)).
		}
	}
	
	RETURN best.
}

FUNCTION mvr_hohmann_intercept {
	// Plots a hohmann intercept to the target.  Assumes circular orbits at same inclination.
	// https://docs.google.com/document/d/1IX6ykVb0xifBrB4BRFDpqPO6kjYiLvOcEo3zwmZL0sQ/edit
	PARAMETER t IS TIME.  // Minimum start time.
	PARAMETER ship IS ship.
	PARAMETER tgt IS target.
	PARAMETER phase IS 0.  // Will 'miss' the target by this # of degrees.
	PARAMETER nd IS FALSE.
	
	LOCAL r1 IS ship:obt:semimajoraxis.
	LOCAL r2 IS tgt:obt:semimajoraxis.
	
	// How many degrees does the target object move during the period of our transfer orbit
	LOCAL theta IS Clamp360(((r1+r2)/(2*r2))^1.5 * 180).
	
	// Figure relative phase angle.
	// Not sure why we need to add 180 to one of these, but if we don't the rendezvous is always 180 degrees off.
	LOCAL p1 IS Clamp360(anom_t2m(180+ship:obt:lan + ship:obt:argumentofperiapsis + obt_anomaly_at_time(t, ship, KA_TRUE), ship)).
	LOCAL p2 IS Clamp360(anom_t2m(tgt:obt:lan + tgt:obt:argumentofperiapsis + obt_anomaly_at_time(t, tgt, KA_TRUE) + theta + phase, tgt)).
	
	PRINT STR_FORMAT("theta={}, p1={}, p2={}", LIST(theta, p1, p2)).
	
	LOCAL ps IS obt_synodic_period(tgt, ship).
	PRINT STR_FORMAT("Current period: {!d}", LIST(ship:obt:period)).
	PRINT STR_FORMAT("Target  period: {!d}", LIST(tgt:obt:period)).
	PRINT STR_FORMAT("Synodic period: {!d}", LIST(ps)).
	
	// Time offset: difference in phase angle / 360 * synodic period.
	LOCAL offset IS Mod2((p2-p1)/360,1) * ps.
	PRINT STR_FORMAT("Time offset:    {!d}", LIST(offset)).
	
	
	RETURN mvr_change_sma(t+offset, (r1+r2)/2, ship, nd).
}
