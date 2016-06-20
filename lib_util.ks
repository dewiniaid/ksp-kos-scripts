@LAZYGLOBAL OFF.
// Utility functions and constants.
GLOBAL K_PI IS constant:pi.  // Shorter!
GLOBAL K_E IS constant:e.  // Shorter!
// Divide to convert degrees to radians, multiply to convert radians to degrees.
GLOBAL K_DEGREES IS 180/K_PI.

GLOBAL K_EPSILON IS 1E-15.

// Units.
GLOBAL K_M IS 1. GLOBAL K_KM IS K_M*1000. GLOBAL K_MM IS K_KM*1000. GLOBAL K_GM IS K_MM*1000.

// Types of anomalies.
GLOBAL KA_MEAN IS 0.
GLOBAL KA_ECC IS 1. GLOBAL KA_ECCENTRIC IS KA_ECC.
GLOBAL KA_TRUE IS 2.
GLOBAL KA_MAX IS KA_TRUE.

// Return t if c else f.
FUNCTION IIF { PARAMETER c. PARAMETER t. PARAMETER f. IF c { RETURN t. } RETURN f. }

// Version of Mod that always returns between [0,m) rather than (-m,m).
FUNCTION Mod2 { PARAMETER v. PARAMETER m. SET v TO MOD(v,m). RETURN IIF(v<0,v+m,v). }

// Clamp angles to 0..360 or -180 to 180.  Requires v >= -360.
FUNCTION Clamp360 { PARAMETER v. RETURN MOD2(v,360). }
FUNCTION Clamp180 { PARAMETER v. RETURN MOD2(v+180,360)-180. }

// Returns b if between a..c, otherwise a or c.  Equivalent to MIN(MAX(a,b),c).
FUNCTION Limit { PARAMETER a. PARAMETER b. PARAMETER c. RETURN MIN(MAX(a,b),c). }
// Returns TRUE if a<=b<=c.
FUNCTION Between { PARAMETER a. PARAMETER b. PARAMETER c. RETURN a<=b AND b<=c. }

// Adds two-argument versions of arccos/arcsin that return negative values when needed.
{
	// Implements asin/acos and limiting versions.
	LOCAL FUNCTION fn {
		PARAMETER f.
		PARAMETER l.  // True: Force values to -1..1
		PARAMETER x.
		PARAMETER y IS 0.
		IF l { SET x TO Limit(-1,x,1). }
		IF y >= 0 { RETURN f(x). }
		RETURN 360-f(x).
	}
	// Wrap a function that expects/returns radians to return degrees.
	LOCAL FUNCTION rw { PARAMETER f. PARAMETER x. RETURN f(x/K_DEGREES)*K_DEGREES. }
	GLOBAL ASIN IS fn@:bind(arcsin@, false).
	GLOBAL ACOS IS fn@:bind(arccos@, false).
	GLOBAL ASINL IS fn@:bind(arcsin@, true).
	GLOBAL ACOSL IS fn@:bind(arccos@, true).
}
FUNCTION SINH { PARAMETER x. SET x TO x/K_DEGREES. RETURN (K_E^x - K_E^(-x))/2. }
FUNCTION COSH { PARAMETER x. SET x TO x/K_DEGREES. RETURN (K_E^x + K_E^(-x))/2. }
FUNCTION ASINH { PARAMETER x. PARAMETER y IS 0. RETURN IIF(y<0,-1,1)*K_DEGREES*LN(x+SQRT(x^2+1)). }
FUNCTION ACOSH { PARAMETER x. PARAMETER y IS 0. RETURN IIF(y<0,-1,1)*K_DEGREES*LN(x+SQRT(x^2-1)). }

// kOS doesn't have any good methods for constructing our own timespan.  Fakery.
GLOBAL K_EPOCH IS TIME-TIME.

// Coerce timespan to seconds or vice versa.  If input is already correct time, return it unchanged.
FUNCTION ToTime { PARAMETER t. IF t:IsType("Timespan") { RETURN t. } RETURN K_EPOCH+t. }
FUNCTION ToSeconds { PARAMETER t. IF t:IsType("Timespan") { RETURN t:seconds. } RETURN t. }

// Relative position
// Orbit or orbitable.
FUNCTION RELPOSITION { PARAMETER s. RETURN s:position - s:body:position. }
// Orbitable only.
// Note: The lack of a second positionat() covering the body is intentional, and has to deal with how kOS does reference frames.
FUNCTION RELPOSITIONAT { PARAMETER s. PARAMETER t. RETURN POSITIONAT(s,t)-ORBITAT(s,t):body:position. }

// Equivalent to A + angleaxis(b, theta), but more accurate.
FUNCTION AngleAxis2 {
	PARAMETER a. //x,y,z
	PARAMETER b. //u,v,w
	PARAMETER theta.
	LOCAL d IS a*b.
	LOCAL c IS COS(theta).
	LOCAL s IS SIN(theta).
	RETURN V(
		b:x*d*(1-c) + a:x*c + (-b:z*a:y+b:y*a:z)*s,
		b:y*d*(1-c) + a:y*c + ( b:z*a:x-b:x*a:z)*s,
		b:z*d*(1-c) + a:z*c + (-b:y*a:x+b:x*a:y)*s
	).	
}

// Update lexicon dst from sequence or lexicon src.  Returns dst.
FUNCTION LEX_UPDATE {
	PARAMETER dst.
	PARAMETER src.
	IF NOT src:istype("Lexicon") {
		SET src TO LEXICON(src).
	}
	FOR k IN src:keys {
		SET dst[k] TO src[k].
	}
	RETURN dst.
}

// Flattens a list of lists into a list.
FUNCTION Flatten {
	PARAMETER lists.
	LOCAL r IS LIST().
	FOR sub IN lists { FOR item IN sub { r:add(item). } }
	RETURN r.
}

// Extend a using elements from b
FUNCTION Extend { PARAMETER a. PARAMETER b. FOR item IN b { a:add(item). } }

// Type-safe comparison
FUNCTION IsTrue  { PARAMETER v. RETURN v:IsType("Boolean") AND v. }
FUNCTION IsFalse { PARAMETER v. RETURN v:IsType("Boolean") AND NOT v. }
	