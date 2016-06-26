@LAZYGLOBAL OFF.
FUNCTION ASCENT_Curve {
	PARAMETER StartAlt.
	PARAMETER EndAlt.
	PARAMETER EndPitch.
	PARAMETER Exponent.  // 0.5 is a circle.
	
	IF ship:altitude <= StartAlt {
		RETURN 90.
	}
	IF ship:altitude >= EndAlt {
		RETURN EndPitch.
	}

	RETURN MAX(0, MIN(90, 90 - ((Ship:Altitude - StartAlt) / (EndAlt - StartAlt))^Exponent * (90 - EndPitch))).
	
	// LOCAL x IS ((ship:altitude)-(StartAlt))/(EndAlt-StartAlt).  // X 0..1
	// RETURN ((MAX(0, 1-(((ship:altitude)-(StartAlt))/(EndAlt-StartAlt))^2))^Exponent * (90-EndPitch)) + EndPitch.
}

FUNCTION ASCENT_LimitTWR {
	PARAMETER TargetTWR.
	LOCAL G IS body:mu / ((ship:altitude + body:radius)^2).
	LOCAL MaxTWR IS ship:availablethrust / (G * ship:mass).
	IF MaxTWR > 0 {
		RETURN MIN(1, TargetTWR/MaxTWR).  // values > 1 don't break KOS
	}
	RETURN 1.
}

FUNCTION ASCENT_TaperTWR {
	PARAMETER TargetTWR.
	PARAMETER FadeStartAlt.
	PARAMETER FadeEndAlt.
	
	IF Ship:Altitude > FadeEndAlt { RETURN 1. }
	LOCAL T IS ASCENT_LimitTWR(TargetTWR).
	IF Ship:Altitude < FadeStartAlt OR T >= 1 { Return T. }
	RETURN T + ((1-T) * ((Ship:Altitude-FadeStartAlt)/(FadeEndAlt-FadeStartAlt))).
}

FUNCTION ASCENT_ApoapsisLimiter {
	PARAMETER ap.
	PARAMETER threshold IS 1000.
	PARAMETER curve IS FALSE.
	SET curve TO IIF(IsFalse(curve), threshold, curve).

	LOCAL correcting IS FALSE.
	
	FUNCTION delegate {
		IF obt:apoapsis >= ap { 
			SET correcting TO FALSE.
			RETURN 0.
		}
		IF obt:apoapsis < ap-threshold {
			SET correcting TO TRUE.
			RETURN 1.
		}
		IF NOT correcting {
			RETURN 0.
		}
		RETURN MAX(0.05, MIN(1, 1-((ap - obt:apoapsis)/curve))).
	}
	RETURN delegate@.
}

FUNCTION ASCENT_WaitForApoapsis {
	PARAMETER minalt.
	PARAMETER ap.
	PARAMETER threshold IS 1000.
	PARAMETER curve IS FALSE.
	SET curve TO IIF(IsFalse(curve), threshold, curve).

	LOCAL lim IS ASCENT_ApoapsisLimiter(ap, threshold, curve).
	LOCK THROTTLE TO lim().
	WAIT UNTIL ship:altitude>minalt AND THROTTLE=0 AND obt:apoapsis+threshold>=ap.
	LOCK THROTTLE TO 0.
}
	
