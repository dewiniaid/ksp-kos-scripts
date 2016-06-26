// Functions for producing various curves for various things that use them.
// Most of the curve functions have a domain and range of [0,1]; all are guarunteed to have that as a minimum.
RUN ONCE lib_util.

FUNCTION curve_normalized {
	PARAMETER fn.
	// Normalized case of a curve function.
	LOCAL minval IS fn(0).
	LOCAL maxval IS fn(1).
	LOCAL dist IS maxval - minval.
	IF dist=0 { SET dist TO 1. } // Avoid div0.
	IF minval=0 AND maxval=1 { RETURN fn@. }  // Already normalized.
	FUNCTION fnwrap {
		PARAMETER x.
		RETURN (fn(x)-minval) / dist.
	}
	RETURN fnwrap@.
}

FUNCTION curve_linear {
	FUNCTION fn {
		PARAMETER x.
		RETURN x.
	}
	RETURN fn@.
}

FUNCTION curve_slope {
	PARAMETER fn.
	PARAMETER resolution IS 0.00001.
	FUNCTION fnwrap {
		PARAMETER x.
		LOCAL x1 IS MAX(x-resolution, 0).
		LOCAL x2 IS MIN(x+resolution, 1).
		LOCAL dy IS fn(x2)-fn(x1).
		RETURN ABS(ARCTAN(dy/(x2-x1))/90).
	}
	RETURN fnwrap@.
}

FUNCTION curve_circular {
	// A circular(ish) curve.
	// Formula: x^a + y^b = 1, except that we subtract y from 1 to maintain the trend of x=0/y=0.
	PARAMETER a IS 2.
	PARAMETER b IS 2.
	SET b TO 1/b.
	FUNCTION fn {
		PARAMETER x.
		RETURN (1-x^a)^b.
	}
	RETURN fn@.
}

FUNCTION curve_invcircular {
	// An inverted circular(ish) curve.
	// Formula: x^a + y^b = 1, except that we subtract y from 1 to maintain the trend of x=0/y=0.
	PARAMETER a IS 2.
	PARAMETER b IS 2.
	SET b TO 1/b.
	FUNCTION fn {
		PARAMETER x.
		RETURN (1-ABS(1-x)^a)^b.
	}
	RETURN fn@.
}

FUNCTION curve_logistic {
	// Logistic curve.  L is fixed at 1.
	PARAMETER k.
	PARAMETER xmin IS 0.
	PARAMETER xmax IS 1.
	PARAMETER normalize IS TRUE.	// Scale such that y=x when x is 0, 1, or -1.  (Unless k=0, when y will always be 0.)
	LOCAL xdist IS xmax-xmin.
	SET k TO k/xdist.
	
	FUNCTION fn {
		PARAMETER x.
		RETURN 1/(K_E^(k*(x-xmin))).
	}
	IF normalize {
		RETURN curve_normalized(fn@).
	}
	RETURN fn@.
}

FUNCTION curve_gompertz {
	// Gompertz function. a is fixed at 1.
	PARAMETER b.
	PARAMETER c.
	PARAMETER normalize IS TRUE.
	
	FUNCTION fn {
		PARAMETER x.
		RETURN K_E^(-b*K_E^(-c*x)).
	}
	IF normalize {
		RETURN curve_normalized(fn@).
	}
	RETURN fn@.
}

FUNCTION curve_scale {
	// Scales a curve function.
	// Inputs < xmin are set to 0.  Inputs > xmax are set to 1.  This logic is reversed if xmin>xmax.
	// Outputs are translated similarly.
	PARAMETER fn.
	PARAMETER xmin IS 0.
	PARAMETER xmax IS 1.
	PARAMETER ymin IS 0.
	PARAMETER ymax IS 1.
	
	LOCAL xdist IS xmax-xmin.
	LOCAL ydist IS ymax-ymin.
	
	FUNCTION fnwrap {
		PARAMETER x.
		SET x TO LIMIT(0, (x-xmin)/xdist, 1).
		RETURN ydist*fn(x) + ymin.	// shouldn't need to limit.
	}
	RETURN fnwrap@.
}
