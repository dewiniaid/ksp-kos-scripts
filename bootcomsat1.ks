@LAZYGLOBAL OFF.
RUN ONCE lib_ascent.
RUN ONCE lib_util.
RUN ONCE lib_obt.
RUN ONCE lib_rt.
RUN ONCE lib_fops.
RUN ONCE lib_mvr.

LOCAL antennarange IS 2.5*K_MM.
LOCAL numsats IS 4.
LOCAL targetsma IS RT_MaxRadius(antennarange, numsats)*0.90.
LOCAL targetapoapsis IS targetsma - body:radius.
LOCAL constellation IS "Comsat K-EL-".

FUNCTION Main {
	SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
	
	LOCAL antennarange IS 2.5*K_MM.
	LOCAL numsats IS 4.
	LOCAL targetsma IS RT_MaxRadius(antennarange, numsats)*0.90.
	LOCAL targetapoapsis IS targetsma - body:radius.
	LOCAL vessels IS Ship_Lexicon(FALSE).
	LOCAL vesselnum IS 1.
	FOR ix IN RANGE(1, numsats+1) {
		SET vesselnum TO ix.
		IF NOT vessels:haskey(constellation+ix) { BREAK. }
		SET TARGET TO vessels[constellation+ix][0].
	}
	SET ship:name TO constellation + vesselnum.
	PRINT "Registering as " + ship:name.
	PRINT "Constellation:   " + constellation.
	PRINT "Antenna range:   " + antennarange.
	PRINT "Satellite count: " + numsats.
	PRINT "Target SMA:      " + targetsma.
	PRINT "Target apoapsis: " + targetapoapsis.
	
	IF vesselnum > 1 {
		PRINT "Will phase with previous vessel; offset=" + (360/numsats) + " degrees.". 
		SET targetapoapsis TO 80000.
		PRINT "New apoapsis:    " + targetapoapsis.
	}
	ELSE { "Will establish initial orbit.". }
	
	WHEN ship:velocity:surface:sqrmagnitude > 100 THEN {
		RT_ToggleAntennas(FALSE).
		PRINT "Antennas stowed for launch.".
	}

	// https://www.reddit.com/r/KerbalSpaceProgram/comments/2quh7m/deltav_to_raise_apoapsis/
	// https://en.wikipedia.org/wiki/Vis-viva_equation
	// http://space.stackexchange.com/questions/1904/how-to-programmatically-calculate-orbital-elements-using-position-velocity-vecto/1919#1919

	WHEN ship:altitude > 50000 THEN {
		RT_ToggleAntennas(TRUE).
		PRINT "Antennas reactivated.".
	}

	// LOCK STEERING TO HEADING(90, ASCENT_Curve(100, 60000, 0, 0.6)).
	//LOCAL steeringcurve IS curve_scale(curve_slope(curve_circular(2,2)), 100, 55000, 90, 0).
	LOCAL steeringcurve IS curve_scale(curve_invcircular(1, 1.5), 100, 60000, 90, 0).
	PRINT "Steering curve at zero is: " + steeringcurve(0).
	PRINT "Steering curve at lots is: " + steeringcurve(200000).

	LOCK STEERING TO HEADING(90, steeringcurve(ship:altitude)).
	
	LOCK THROTTLE TO ASCENT_TaperTWR(2.0, 25000, 35000).
	PRINT "Lift-off.".
	STAGE.

	WAIT UNTIL ship:availablethrust = 0.
	PRINT "Jettisoning first stage.".
	STAGE.
	// Burn to current target apoapsis.
	LOCAL throttlecurve IS curve_scale(curve_circular(2,2), MAX(70000, targetapoapsis-15000), targetapoapsis).
	LOCK THROTTLE TO throttlecurve(ship:apoapsis).
	WAIT UNTIL ship:apoapsis >= targetapoapsis AND ship:altitude > 70000.
	UNLOCK THROTTLE.
	SET warpmode TO "RAILS".
	
	IF vesselnum<>1 {
		// We're not the first vessel, so we're in a staging orbit.
		// Circularize, then plan hohmann.
		PRINT "Atmosphere exited; apoapsis at staging target.".
		
		// Circularize at AP
		LOCAL nd IS mvr_change_sma(obt_next_anomaly(180), ship:apoapsis+body:radius).
		ADD nd.
		fops_execute(nd, 10).
		
		// Plan hohmann transfer.
		LOCAL nd IS mvr_hohmann_intercept(Time+30, ship, target, 360/numsats).
		ADD nd.
		fops_execute(nd, 10).
	}
	// Final circularization at apoapsis.
	LOCAL nd IS mvr_change_sma(obt_next_anomaly(180), targetsma).
	ADD nd.
	fops_execute(nd, 10).
	
	// Fine tuning.
	PRINT "Fine-tuning semi-major axis.".
	WAIT 0.
	PRINT "Current: " + obt:semimajoraxis.
	PRINT "Target:  " + targetsma.
	LOCAL sign IS IIF(obt:semimajoraxis < targetsma, 1, -1).
	PRINT "Sign: " + sign.
	LOCK STEERING TO LookDirUp(ship:velocity:orbit * sign, ship:facing:upvector).
	WAIT UNTIL fops_steering_stable().
	PRINT "Beginning burn.".
	SET throttlecurve TO curve_scale(curve_invcircular(2,2), 0, 5000, 0.0001, 0.02).
	LOCK THROTTLE TO MAX(0.0001, throttlecurve(ABS(obt:semimajoraxis - targetsma))).
	WAIT UNTIL obt:semimajoraxis*sign > targetsma*sign.
	UNLOCK THROTTLE.
	UNLOCK STEERING.
	PRINT "Initial orbit program completed!".
}

LOCAL deadline IS TIME+10.
WAIT UNTIL time>deadline OR ship:control:pilotroll<>0.
IF ship:control:pilotroll>=0 { 
	Main(). 
}
