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

// Returns time to next LAN.


// MJ port.
FUNCTION clamp360 { PARAMETER v. RETURN mod(v+360,360). }
FUNCTION clamp180 { PARAMETER v. RETURN mod(v+540,360)-180. }
	
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
	LOCAL hdg IS arccos(costarget).
	IF inc<0 { SET hdg TO -hdg. }
	RETURN Clamp360(90 - hdg).	// 360+90-...
}

// Changes inclination.
FUNCTION mvr_inclination {
	PARAMETER t.  // Maneuver time.
	PARAMETER inc.  // Target inclination
	PARAMETER ship IS ship.  // Can be any orbital.

	LOCAL vel IS VELOCITYAT(ship, t):orbit.
	LOCAL obt IS ORBITAT(ship, t).
	LOCAL r IS POSITIONAT(ship, t) - POSITIONAT(obt:body, t).
	LOCAL b IS basis_une(vel, r).
	LOCAL hdg IS heading_for_inclination(inc, ARCSIN(r:y/r:mag)).
	LOCAL hvel IS VXCL(b[0], vel).	// actualHorizontalVelocity.
	// LOCAL hvel IS vel.
	LOCAL n IS b[1]*hvel:mag*cos(hdg).	// North component
	LOCAL e IS b[2]*hvel:mag*sin(hdg). // eastComponent
	LOCAL lvel IS basis_transform(b, vel).
	LOCAL hvel IS V(0,lvel:y,lvel:z).
	LOCAL tvel IS V(lvel:x,hvel:mag*cos(hdg),hvel:mag*sin(hdg)).
	IF (vel:y<0)=(Clamp180(inc)>0) {
		SET tvel:y TO -tvel:y.
	}
	LOCAL mvr IS basis_transform(basis_for_ship(ship, t), basis_transform(b, tvel-lvel, true)).
	RETURN NODE(t:seconds, mvr:x, mvr:y, mvr:z).
	
	LOCAL b IS basis_for_ship(ship, t).
	LOCAL hvel IS VXCL(b[0], vel).
	LOCAL mvr IS basis_transform(b, hvel).
	SET mvr TO V(0, mvr:mag*cos(hdg), mvr:mag*sin(hdg))-mvr.
	RETURN NODE(t:seconds, mvr:x, mvr:y, mvr:z).
}
