@LAZYGLOBAL OFF.
RUN ONCE lib_basis.

// Change semimajor axis at time.
FUNCTION mvr_semimajoraxis {
	PARAMETER t.  // Maneuver time.
	PARAMETER target_sma.
	PARAMETER ship IS ship.  // Can be any orbital.
	
	LOCAL obt IS ORBITAT(ship, t).
	LOCAL b IS obt:body.
	LOCAL r IS (POSITIONAT(ship, t) - POSITIONAT(b, t)):mag.
	IF r > target_sma {
		PRINT "*** WARNING: attempted to plot a maneuver where target_sma < height.".
		RETURN.
	}
	LOCAL dV IS SQRT(b:mu * (2/r - 1/target_sma)) - SQRT(b:mu * (2/r - 1/obt:semimajoraxis)).
	RETURN NODE(t:seconds, 0, 0, dV).
}

// Determines the true anomaly where a particular altitude will occur.  
// (Subtract the result from 360 to get the other possible answer).
// Must be pe_radius <= radius <= ap_radius
FUNCTION anomaly_at_radius {
	PARAMETER radius.
	PARAMETER orb IS obt.
	
	IF radius < (orb:periapsis + orb:body:radius) OR radius > (orb:apoapsis+orb:body:radius) {
		PRINT "*** WARNING: attempted to find true anomaly at a radius not within pe <= radius <= ap".
		RETURN.
	}
	RETURN ARCCOS((((orb:semimajoraxis*(1-orb:eccentricity^2))/radius) - 1)/orb:eccentricity).
}

// Returns -obt:inclination if we're on the DN side of the orbit.


// Changes inclination.  Math is currently only correct if executed at LAN/DAN.
FUNCTION mvr_inclination {
	PARAMETER t.  // Maneuver time.
	PARAMETER target_inc.
	PARAMETER ship IS ship.  // Can be any orbital.
	
	LOCAL b IS basis_from_ship(ship, t).
	LOCAL vel IS VELOCITYAT(ship, t):orbit.
	LOCAL obt IS ORBITAT(ship, t).
	LOCAL mvr IS basis_transform(b, (vel + angleaxis(obt:inclination - target_inc, b[2]))-vel).
	RETURN NODE(t:seconds, mvr:z, mvr:y, mvr:x).
}

REMOVE n.
WAIT 0.
LOCAL n IS mvr_inclination(time+eta:apoapsis, 15).
PRINT n.
ADD n.

REMOVE n.
WAIT 0.
LOCAL n IS mvr_inclination(time, 0).
PRINT n.
ADD n.
PRINT MOD(obt:argumentofperiapsis + obt:trueanomaly, 360).


