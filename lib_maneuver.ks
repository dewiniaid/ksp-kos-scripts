@LAZYGLOBAL OFF.
RUN ONCE lib_util.
RUN ONCE lib_basis.
RUN ONCE lib_obt.
RUN ONCE lib_string.

// A maneuver plan is a list of maneuvers in (translated) vector form,
// The list contains 3 elements per maneuver: 
// - vector (on the correct basis, so it can be converted using vector_to_node()
// - time

// Returns total dV across all maneuvers in a plan (or a single maneuver structure).
FUNCTION plan_tdv {
	PARAMETER plan.
	LOCAL dv IS 0.
	FOR ix IN RANGE(0,plan:length,2) {
		SET dv TO dv+plan[ix]:mag.
	}
	RETURN dv.
}

// Choose most efficient plan.
// Accepts either two plans, or a list of plans.
FUNCTION plan_choose {
	PARAMETER p1.
	PARAMETER p2 IS 0.
	
	IF p1[0]:istype("List") {
		LOCAL best_plan IS LIST().
		LOCAL best_dv IS 0.
		FOR p IN p1 {
			LOCAL dv IS plan_tdv(p).
			IF best_dv=0 OR best_dv>dv { SET best_dv TO dv. SET best_plan TO p. }
		}
		RETURN best_plan.
	}
	
	RETURN IIF(plan_tdv(p1) < plan_tdv(p2), p1, p2).
}

FUNCTION plan_add {
	PARAMETER plan.
	FOR ix IN RANGE(0,plan:length,2) {
		ADD vector_to_node(plan[ix], ToSeconds(plan[ix+1])).
	}
}

FUNCTION plan_mintime { PARAMETER p. RETURN p[1]. }
FUNCTION plan_maxtime { PARAMETER p. RETURN p[p:length-1]. }

FUNCTION plan_predict {
	PARAMETER o.
	PARAMETER p.
	FOR ix IN RANGE(0,p:length,2) {
		SET o TO orb_predict(o, p[ix], p[ix+1]).
	}
	RETURN o.
}

FUNCTION node_has_nextnode {
	LOCAL sentinel IS NODE(TIME:Seconds+2^32,42,1337,359).
	ADD sentinel.
	LOCAL r IS NEXTNODE<>sentinel.
	REMOVE sentinel.
	RETURN r.
}

FUNCTION node_clear {
	LOCAL sentinel IS NODE(TIME:Seconds+2^32,42,1337,359).
	ADD sentinel.
	UNTIL NEXTNODe=sentinel { REMOVE NEXTNODE. }
	REMOVE sentinel.
}

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
	RETURN LIST(V(0, 0, SQRT(o["mu"] * (2/o["rmag"] - 1/a)) - SQRT(o["mu"] * (2/o["rmag"] - 1/o["sma"]))), t).
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
	RETURN LIST(basis_transform(basis_mvr(o), vel-o["v"]), t).
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
	RETURN LIST(basis_transform(basis_mvr(o), e+n-hvel), t).
}

// Change inclination, efficiently.  Tries multiple options.  Returns a list of nodes to execute.
FUNCTION mvr_inclination_ex {
	PARAMETER t.  // Earliest maneuver time.
	PARAMETER inc. // Target inclination.
	PARAMETER o IS ship.  // Any orbital, Orbit or Orb.
	PARAMETER raisealt IS TRUE.
	
	LOCAL o IS orb_from_orbit(o).
	LOCAL anode IS IIF(o["argp"]<90 OR o["argp"]>270,0,180)-o["argp"].
	LOCAL tnode IS orb_next_anomaly(anode,o,t,KA_TRUE).
	LOCAL plan IS mvr_inclination(tnode,inc,o).
	LOCAL can IS 0.
	LOCAL fmt IS str_formatter("{:20}: dV={:6.1}m/s").
	//PRINT fmt(LIST("LAN/DN", plan_tdv(plan))).
	LOCAL thigh IS 0.
	LOCAL ahigh IS -1.
	LOCAL ans IS -1.
	
	
	IF inc<>0 {
		SET ahigh TO 180.
		SET thigh TO ToSeconds(orb_next_anomaly(ahigh,o,t,KA_TRUE)).
		LOCAL sininc IS ABS(SIN(inc)).
		IF ABS(SIN(orb_latitude_at_anomaly(ahigh,o))) > sininc {
			// AP is too high of latitude.  Figure out the anomaly of the nearest location at correct latitude.
			// at 0<=argp<180, pe is in the north, thus ap is in the south (negative latitudes).
			LOCAL lat IS IIF(0 <= o["argp"] AND o["argp"] < 180, -inc, inc).
			LOCAL m1 IS orb_anomaly_at_latitude(lat,o,KA_TRUE,false).
			LOCAL m2 IS orb_anomaly_at_latitude(lat,o,KA_TRUE,true).
			
			// Find time to the higher value.
			SET ahigh TO IIF(ABS(m1-180)<ABS(m2-180),m1,m2).
			SET thigh TO orb_next_anomaly(ahigh,o,t,KA_TRUE).
		}
		SET can TO mvr_inclination(thigh,inc,o).
		SET plan TO plan_choose(plan, can).
		//PRINT fmt(LIST("High", plan_tdv(can))).
		IF ABS(SIN(o["inc"])) < sininc {
			SET ans TO Clamp360(IIF(0 > Clamp360(o["argp"]) AND Clamp360(o["argp"]) >= 180,90,270)-o["argp"]).
			SET can TO mvr_inclination(orb_next_anomaly(ans,o,t,KA_TRUE),inc,o).
			//PRINT fmt(LIST("North/South", plan_tdv(can))).
			SET plan TO plan_choose(plan, can).
		}
	}
	IF NOT raisealt { RETURN plan. }
	LOCAL orbits IS LIST(orb_at_anomaly(0,o,t), orb_at_anomaly(180+anode,o,t)).
	IF ahigh<>-1 AND ahigh<>180 { orbits:ADD(orb_at_anomaly(180+ahigh,o,t)). }
	IF ans<>-1 { orbits:ADD(orb_at_anomaly(180+ans,o,t)). }

	LOCAL bestdv IS plan_tdv(plan).
	LOCAL tdv IS bestdv.
	FOR i IN RANGE(1,6) {
		LOCAL dv IS ROUND(tdv*0.1*i,2).
		LOCAL mvr IS V(0,0,dv).
		PRINT " ".
		PRINT "Testing effects of adding " + dv + " dV...".
		PRINT STR_FORMAT("Actual orbit: ap={:.2} pe={:.2}.", LIST(obt:apoapsis, obt:periapsis)).
		FOR obase IN orbits {
			LOCAL otime IS obase["epoch"].
			PRINT STR_FORMAT("Orbit at {!d}: ap={:.2} pe={:.2}.", LIST(otime, obase["ap"]-obt:body:radius, obase["pe"]-obt:body:radius)).
			LOCAL burnalt IS orb_radius_at_time(otime,obase).
			PRINT "burn altitude is: " + burnalt.
			LOCAL oprime IS orb_predict(obase, mvr, otime).
			PRINT STR_FORMAT("Predicted: ap={:.2} pe={:.2}.", LIST(oprime["ap"]-obt:body:radius, oprime["pe"]-obt:body:radius)).
			IF oprime["ecc"]<1 AND oprime["ap"] < oprime["body"]:soiradius {
				LOCAL can IS mvr_inclination_ex(otime, inc, oprime, FALSE).
				LOCAL candv IS plan_tdv(can)+2*dv.
				IF candv < bestdv {
					SET oprime TO plan_predict(oprime, can).
					LOCAL ta IS orb_anomaly_at_radius(burnalt, o).
					SET plan TO Flatten(LIST(LIST(mvr, otime), can, LIST(-mvr, otime+oprime["period"]))).
					SET bestdv TO candv.
				}
			}
		}
	}
	RETURN plan.
}

LOCAL p IS (mvr_inclination_ex(time, 90)).
PRINT p.
PRINT plan_tdv(p).
PLAN_ADD(p).
