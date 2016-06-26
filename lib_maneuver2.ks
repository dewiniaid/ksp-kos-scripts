@LAZYGLOBAL OFF.
RUN ONCE lib_util.
RUN ONCE lib_basis.
RUN ONCE lib_obt.
RUN ONCE lib_string.
RUN ONCE lib_iter.

// Plan:
// LIST of
// LIST(node, fn)

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
	UNTIL NEXTNODE=sentinel { REMOVE NEXTNODE. }
	REMOVE sentinel.
}

FUNCTION node_tdv {
	PARAMETER nd.
	RETURN SQRT(nd:radialout^2+nd:normal^2+nd:prograde^2).
}

FUNCTION plan_tdv {
	PARAMETER plan.
	LOCAL dv IS 0.
	FOR item IN plan { SET dv TO dv + node_tdv(item[0]). }
	RETURN dv.
}

FUNCTION plan_choose {
	PARAMETER p1.
	PARAMETER p2 IS 0.
	PARAMETER copywinner IS 0.  // Copies the winning plan if: p1 wins and this is 1 or 3, or p2 wins and this is 2 or 3.
	IF p1[0][0]:istype("List") {
		LOCAL best_plan IS LIST().
		FOR p IN p1 {
			LOCAL dv IS plan_tdv(p).
			IF best_dv=0 OR best_dv>dv { SET best_dv TO dv. SET best_plan TO p. }
		}
		RETURN best_plan.
	}
	RETURN IIF(plan_tdv(p1) < plan_tdv(p2), p1, p2).
}

// Deep copy a plan.
FUNCTION plan_copy {
	PARAMETER src.
	LOCAL dst IS LIST().
	FOR item IN src {
		dst:add(LIST(node_copy(item[0]), item[1])).
	}
	RETURN dst.
}

FUNCTION plan_add {
	PARAMETER plan.
	FOR item IN plan { ADD item[0]. }
}

FUNCTION plan_sync {
	PARAMETER plan.
	PARAMETER t IS TIME.
	node_clear().
	FOR item IN plan {
		PRINT STR_FORMAT("{!t} {}", LIST(t, item)).
		
		node_copy(item[1](t)[0][0], item[0]).
		SET t TO MAX(ToSeconds(t), ToSeconds(item[0]:eta+TIME)).
		ADD item[0].
	}
}

// Change semimajor axis at time.
FUNCTION nd_change_sma {
	PARAMETER t.  // Maneuver time.
	PARAMETER a.  // New semimajor axis.
	PARAMETER ship IS ship.
	PARAMETER nd IS FALSE.  // Node to update in place.
	SET o TO ORBITAT(ship, ToSeconds(t)).
	LOCAL rmag IS RELPOSITIONAT(ship,ToSeconds(t)):mag.
	IF a < rmag {
		PRINT STR_FORMAT("*** WARNING: cannot reduce semi-major axis below the altitude of the burn. ({a < {})", LIST(a, rmag)).
		RETURN FALSE.
	}
	RETURN vector_to_node(t, V(0, 0, SQRT(o:body:mu*(2/rmag - 1/a)) - SQRT(o:body:mu * (2/rmag - 1/o:semimajoraxis))), nd).
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
		
	RETURN LIST(vector_to_node(basis_transform(basis_mvr(opos,ovel), vel-ovel), t, nd), _rebuild@).
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
	LOCAL o IS ORBITAT(ship, ToSeconds(t)).
	PARAMETER nd IS FALSE.  // Node to update in place.
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
	FUNCTION _rebuild {
		PARAMETER t.
		PRINT "REBUILD: rmag is " + r:mag.
		RETURN mvr_set_apsis(dir, t, r:mag, z, ship).
	}
	IF r=z {
		// The normal method produces a singularity, so workaround this.
		IF dir>0 { // r is apoapsis.
			RETURN LIST(LIST(nd_change_sma(t, (r:mag+o:periapsis+o:body:radius)/2, ship, nd), _rebuild@)).  // radius is already implicit in r/z, but we need to add one copy of it.
		} ELSE {
			RETURN LIST(LIST(nd_change_sma(t, (r:mag+o:apoapsis+o:body:radius)/2, ship, nd), _rebuild@)).
		}
	}
	LOCAL v IS VELOCITYAT(ship, t):orbit.
	LOCAL ycos IS VCRS(r,v):mag/(r:mag*v:mag).
	RETURN LIST(LIST(vector_to_node(V(0, 0, SQRT((2*body:mu*z*(z-r:mag))/(r:mag*z^2-r:mag^3*ycos^2))-v:mag), t, nd), _rebuild@)).
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
FUNCTION nd_inclination {
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

// Changes inclination.
FUNCTION mvr_inclination {
	PARAMETER t.  // Maneuver time.
	PARAMETER inc.  // Target inclination
	PARAMETER ship IS ship.
	PARAMETER nd IS FALSE.  // Optional maneuver node to update in-place.
	FUNCTION _rebuild {
		PARAMETER t.
		RETURN mvr_inclination(MAX(ToSeconds(t), Time:Seconds), inc, ship).
	}
	RETURN LIST(LIST(nd_inclination(t, inc, ship, nd), _rebuild@)).
}

// Change inclination, efficiently.  Tries multiple options.  Returns a list of nodes to execute.
FUNCTION mvr_inclination_ex {
	PARAMETER t.  // Earliest maneuver time.
	PARAMETER inc. // Target inclination.
	PARAMETER ship IS ship.
	PARAMETER multinode IS TRUE.	// Allow multinode plans?
	PARAMETER nd IS FALSE.  // (Sort of) update maneuver in place.
	SET t TO ToSeconds(t).
	LOCAL o IS ORBITAT(ship, ToSeconds(t)).
	LOCAL argp IS o:argumentofperiapsis.
	FUNCTION _rebuild {
		PARAMETER t.
		RETURN mvr_inclination_ex(MAX(ToSeconds(t), Time:Seconds), inc, ship, FALSE).
	}
	
	// Higher of LAN/LDN.
	//LOCAL m_node IS IIF(BETWEEN(90, argp, 270), 180, 0) - argp.
	//LOCAL t_node IS obt_next_anomaly(m_node,o,t).
	//LOCAL best IS LIST(mvr_inclination(t_node,inc,o)).
	LOCAL best IS LIST(LIST(nd_inclination(obt_next_latitude(0, o, t, FALSE, 1), inc, ship), _rebuild@)).
	
	LOCAL can IS 0.
	LOCAL fmt IS str_formatter("{:20}: dV={:6.1}m/s").
	//PRINT fmt(LIST("LAN/DN", plan_tdv(plan))).
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
		SET best TO plan_choose(best, LIST(LIST(nd_inclination(t_high,inc,ship), _rebuild@))).
		IF ABS(SIN(o:inclination)) < sininc {
			// Sometimes it may be worthwhile to check the northernmost/southernmost points of the orbit.
			// (whichever is highest)
			SET m_ns TO Clamp360(IIF(BETWEEN(0, Clamp360(argp), 180), 90, 270) - argp).
			SET t_ns TO obt_next_anomaly(m_ns,o,t).
			SET best TO plan_choose(best, LIST(LIST(nd_inclination(t_ns,inc,ship), _rebuild@))).
		}
	}
	
	IF NOT multinode OR o:apoapsis+1000 >= body:soiradius OR o:apoapsis < 0 {
		IF NOT IsFalse(nd) { SET best[0][0] TO node_copy(best[0][0], nd). }
		RETURN best.
	}
	node_clear().  // Clear existing nodes, since they'll muck up a lot of other things anyways.
	
	// Determine candidate times for raising Ap.
	LOCAL times IS LIST(obt_next_anomaly(0,o,t)).
	IF o:eccentricity<=1 {
		times:ADD(obt_next_anomaly(180,o,t)).
		IF m_high<>180 { times:ADD(obt_next_anomaly(m_high+180,o,t)). }
		IF m_ns<>-1 { times:ADD(obt_next_anomaly(180+m_ns,o,t)). }
	}
	PRINT "Best plan:".
	PRINT best.
	LOCAL best_dv IS plan_tdv(best).
	PRINT best_dv.
	PRINT "---".
	
	
	// Precreate plan
	LOCAL nd_up IS NODE(0,0,0,0).
	LOCAL nd_down IS NODE(0,0,0,0).
	LOCAL nd_mvr IS NODE(0,0,0,0).
	LOCAL plan IS LIST(LIST(nd_up, FALSE), LIST(nd_mvr, FALSE), LIST(nd_mvr, FALSE)).
	LOCAL oap IS obt:apoapsis+body:radius.
	
	FOR burntime IN times {
		// Harmless to do these even if they're not added yet.
		// FOR p IN plan { REMOVE p[0]. }
		LOCAL burnheight IS obt_radius_at_time(burntime, ship).
		PRINT STR_FORMAT("Burn time: {!t} -- height: {}", LIST(burntime, burnheight)).
		
		FUNCTION _triburn_plan {
			PARAMETER ap. // Target apoapsis.
			SET plan[0] TO mvr_set_apoapsis(burntime, burnheight, ap, ship, nd_up)[0].
			ADD nd_up.
			SET plan[1] TO mvr_inclination_ex(burntime+1, inc, ship, FALSE, nd_mvr)[0].
			ADD nd_mvr.
			SET plan[2] TO mvr_set_apsis(0, TIME+nd_mvr:eta+1, burnheight, oap, ship, nd_down)[0].
			WAIT 0.
			REMOVE nd_mvr.
			REMOVE nd_up.
			WAIT 0.
			RETURN plan_tdv(plan).
		}
		
		// Determine initial maxdv for burn.
		// It can't be more than half the best plan, since we need to reverse it afterwards.
		LOCAL maxap IS o:body:soiradius-1000.
		LOCAL dv IS _triburn_plan(maxap).
		PRINT dv.
		PRINT nd_up:prograde.
		IF dv>best_dv {
			ADD nd_up.
			SET nd_up:prograde TO best_dv/2.
			
			LOCAL dv IS nd_up:prograde*2 + node_tdv(nd_inclination(burntime+1, inc, ship, nd_mvr)).
			LOCAL excess IS dv - best_dv.
			PRINT STR_FORMAT("max dvP for SOI: {}  best_dv: {}", LIST(nd_up:prograde, best_dv)).
			UNTIL nd_up:prograde <= 0 OR excess <= 0 {
				SET nd_up:prograde TO nd_up:prograde - (excess/2).
				SET dv TO nd_up:prograde*2 + node_tdv(nd_inclination(burntime+1, inc, ship, nd_mvr)).
				SET excess TO dv - best_dv.
				PRINT STR_FORMAT("Init: dvP={}; excess={}", LIST(nd_up:prograde, excess)).
			}
			IF nd_up:prograde > 0 {
				SET maxap TO nd_up:orbit:apoapsis + nd_up:orbit:body:radius.
				SET dv TO _triburn_plan(maxap).
			}
			REMOVE nd_up.
		}
		PRINT nd_up:prograde.
		IF nd_up:prograde > 0 {
			PRINT "*".
			LOCAL threshold iS 1.
			LOCAL curvestep IS 1.
			// Successfully found a valid plan.  Update our best plan if it makes sense to do so.
			IF dv < best_dv {
				PRINT "Setting new record.".
				SET best_dv TO dv.
				SET best TO plan_copy(plan).
				PRINT best.
			}			
			IF _triburn_plan(maxap - curvestep) < dv {
				// Better curve if we go to lower values, so begin binary search.
				LOCAL minap IS 0.
				LOCAL lastdv IS 0.
				UNTIL lastdv<>0 AND (lastdv-dv) < threshold {
					// Figure total dV at trial height.
					LOCAL ap IS (minap+maxap)/2.
					SET lastdv TO dv.
					LOCAL dv IS _triburn_plan(ap).
					PRINT STR_FORMAT("Refine: ap={}; dv={}", LIST(ap, dv)).
					IF dv < best_dv {
						SET best_dv TO dv.
						SET best TO plan_copy(plan).
						PRINT "Setting new record.".
						PRINT best.
					}
					// Check curve direction.
					IF dv > _triburn_plan(ap+curvestep) {
						SET maxap TO ap.
					} ELSE {
						SET minap TO ap.
					}
				}
			} ELSE {
				PRINT "Curve still descending, skipping binary search.".
			}
		}
	}
	RETURN best.
}

node_clear().

LOCAL p IS mvr_inclination_ex(time, 90).
plan_add(p).
// plan_sync(p).
//PRINT p.
//PRINT plan_tdv(p).
//PLAN_ADD(p).
