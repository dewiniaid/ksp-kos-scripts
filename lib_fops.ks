// Flight OPerationS Library.
//
// While lib_mvr mostly concerns planning maneuvers and handling nodes, lib_fops 
// handles the actual execution elements; i.e. controlling the ship and other things based on
// ship state.
//
// lib_fops also contains some maneuvering code for some special cases like SMA/AP/PE burns
// that terminate based on the condition rather than based on the node being fully executed.
// These are more accurate in some cases.
RUN ONCE lib_curve.
RUN ONCE lib_mvr.

// Helpers
FUNCTION fops_dv {
	// Takes a node, vector, or scalar and returns the scalar delta-V required.
	PARAMETER item IS FALSE.
	IF IsFalse(item) { 
		IF NOT HASNODE { RETURN 0. }
		RETURN nextnode:deltav:mag.
	}
	IF item:IsType("Node") { RETURN node_dv(item). }
	IF item:IsType("Vector") { RETURN item:mag. }
	RETURN item.
}
FUNCTION fops_t {
	// Returns node time, or t if the input is not a node.
	PARAMETER item IS FALSE.
	PARAMETER t IS FALSE.
	IF IsFalse(item) { 
		IF NOT HASNODE { RETURN 0. }
		RETURN nextnode:eta+time:seconds.
	}
	IF item:IsType("Node") {
		RETURN item:eta+time:seconds.
	}
	RETURN ToSeconds(t).
}
	
FUNCTION fops_burntime {
	// Time to complete a maneuver of a given dv.
	// Adapted from https://github.com/gisikw/ksprogramming/blob/master/library/maneuver.ks
	PARAMETER dv IS FALSE.  // Delta-V, node, or vector.  If a node, 't' is ignored and the node time is used instead.  Defaults to nextnode (safely).
	PARAMETER ship IS ship.
	PARAMETER t IS FALSE.  // Time of execution.  Ignored if dv isa node.
	SET t TO fops_t(dv, t).
	SET dv TO fops_dv(dv).
	
	//LOCAL mu IS ORBITAT(ship, t):body:mu.
	//LOCAL r IS RELPOSITIONAT(ship, t):mag.

	// The original source multiplies f and m by 1000 (to convert to kilograms and kilonewtons^2, presumably).
	// Since m*(lots of other things) is divided by f, the two multiplications ultimately cancel.
	//LOCAL f IS ship:availablethrust.
	//LOCAL m IS ship:mass.
	//LOCAL p IS Ship_AverageISP(ship).
	//LOCAL g IS mu/r^2.
	LOCAL gp IS Ship_AverageISP(ship) * ORBITAT(ship, t):body:mu / RELPOSITIONAT(ship, t):sqrmagnitude.
    //RETURN g*m*p * (1 - K_E^(-dv/(g*p))) / f.
	RETURN gp*ship:mass * (1 - K_E^(-dv/gp)) / ship:availablethrust.
}

FUNCTION fops_halfburntime {
	// Time to complete a maneuver of a given dv, halved.
	// Adapted from https://github.com/gisikw/ksprogramming/blob/master/library/maneuver.ks
	PARAMETER dv IS FALSE.  // Delta-V, node, or vector.  If a node, 't' is ignored and the node time is used instead.  Defaults to nextnode (safely).
	PARAMETER ship IS ship.
	PARAMETER t IS FALSE.  // Time of execution.  Ignored if dv isa node.
	SET t TO fops_t(dv, t).
	SET dv TO fops_dv(dv) / 2.
	LOCAL gp IS Ship_AverageISP(ship) * ORBITAT(ship, t):body:mu / RELPOSITIONAT(ship, t):sqrmagnitude.
	RETURN gp*ship:mass * (1 - K_E^(-dv/gp)) / ship:availablethrust.
}

FUNCTION fops_burntime_fn {
	// Snapshots state and returns a function(dv) that returns time to complete a burn.
	// Intended for rapid calls; faster than fops_burntime in the repeated-call case.
	PARAMETER ship IS ship.
	LOCAL p IS Ship_AverageISP(ship).
	
	FUNCTION delegate {
		PARAMETER dv.
		LOCAL gp IS p * Body:mu / (Ship:Altitude + Body:radius)^2.
		RETURN gp*ship:mass * (1 - K_E^(-dv/gp)) / ship:availablethrust.
	}
	RETURN delegate@.
}

GLOBAL fops_execute_options IS LEXICON(
	"tolerance", 0.1,	// Point at which maneuver is considered completed.
	"begin_angle", 0.1,	// Don't initiate/resume burning until we're this close to the target angle
	"abort_angle", 10,	// Continue burning as long as we're still this close to the target angle
	"feather_time", 0.5, // Feather throttle when remaining burn time (at full throttle) is less than this # of seconds.
	"feather_min", 0.01, // Minimum throttle pct for feathering when active.
	"feather_curve", curve_gompertz(2,5),
	"avel_tolerance", 0.01  // Angular velocity must drop below this before we consider ourselves stable.
).

LOCAL _laststeeringcheck IS 0.
FUNCTION fops_steering_stable {
	PARAMETER avel_tolerance IS 0.01.
	PARAMETER angleerror IS 0.5.
	LOCAL t IS time:seconds.
	IF t - _laststeeringcheck >= 1 {
		SET _laststeeringcheck TO t.
		PRINT STR_FORMAT("angleerror={}; tolerance={}; avel={}; avel_tolerance={}", LIST(SteeringManager:angleerror, angleerror, ship:angularvel:mag, avel_tolerance)).
	}
	// Returns TRUE when angleerror and angular velocity are within tolerances.
	RETURN ABS(SteeringManager:angleerror) < angleerror AND ship:angularvel:sqrmagnitude < avel_tolerance^2.
}

FUNCTION fops_execute {
	// Execute planned maneuver.
	PARAMETER nd IS FALSE.
	PARAMETER warpthreshold IS FALSE.  // Amount of buffer on warpto.  FALSE disables warp.
	PARAMETER opts IS fops_execute_options.
	IF IsFalse(nd) {
		IF NOT HASNODE { RETURN. }
		SET nd TO NEXTNODE.
	}
	LOCAL nodetime IS time:seconds+nd:eta.
	LOCAL burn_duration IS fops_burntime(nd).
	LOCAL exectime IS nodetime - fops_halfburntime(nd).
	LOCAL tolerance IS opts["tolerance"]^2.  // Allows us to compare sqrmagnitude instead of magnitude, faster.
	LOCAL avel_tolerance IS opts["avel_tolerance"]^2.
	
	// Initial pointing.
	LOCK STEERING TO LOOKDIRUP(nd:deltav, ship:facing:upvector).
	WAIT 0.
	PRINT "Waiting for steering alignment...".
	// LOCAL _abort IS FALSE.
	// PRINT STR_FORMAT("angleerror={}; begin_angle={}; avel={}; avel_tolerance={}", LIST(SteeringManager:angleerror, opts["begin_angle"], ship:angularvel:mag, sqrt(avel_tolerance))).
	// ON ROUND(time:seconds) {
	// 	PRINT STR_FORMAT("angleerror={}; begin_angle={}; avel={}; avel_tolerance={}", LIST(SteeringManager:angleerror, opts["begin_angle"], ship:angularvel:mag, sqrt(avel_tolerance))).
	// 	IF NOT _abort { PRESERVE. }
	// }
	WAIT UNTIL fops_steering_stable().
	// SET _abort TO TRUE.
	
	PRINT "Warping to burn.".
	IF NOT IsFalse(warpthreshold) {
		UNLOCK STEERING. // Save power.
		WARPTO(exectime - warpthreshold).
		LOCK STEERING TO LOOKDIRUP(nd:deltav, ship:facing:upvector).
	}
	PRINT "Warp complete".
	// Throttle curve.
	LOCAL curve_fn IS curve_scale(opts["feather_curve"], 0, opts["feather_time"]).
	LOCAL burntime_fn IS fops_burntime_fn().
	// Set up throttle fn.
	PRINT "Waiting " + (exectime-TIME:seconds) + " sec.".
	WAIT exectime-TIME:seconds.
	UNTIL FALSE {
		PRINT "Aligning.".
		WAIT UNTIL fops_steering_stable().
		LOCK THROTTLE TO MAX(opts["feather_min"], curve_fn(burntime_fn(nd:deltav:mag))).
		PRINT "Throttle locked, value=" + THROTTLE.
		WAIT UNTIL nd:deltav:sqrmagnitude < tolerance OR ABS(SteeringManager:AngleError) > opts["abort_angle"].
		UNLOCK THROTTLE.
		PRINT "Thrrottling down.".
		IF nd:deltav:sqrmagnitude < tolerance {
			PRINT "Burn complete.".
			UNLOCK STEERING.
			REMOVE nd.
			BREAK.
		}
	}
}
