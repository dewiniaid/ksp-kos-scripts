@LAZYGLOBAL OFF.
// Utility functions and constants.
GLOBAL K_PI IS constant():pi.  // Shorter!
// Divide to convert degrees to radians, multiply to convert radians to degrees.
GLOBAL K_DEGREES IS 180/K_PI.

GLOBAL K_EPSILON IS 1E-15.

// Units.
GLOBAL K_M IS 1. GLOBAL K_KM IS K_M*1000. GLOBAL K_MM IS K_KM*1000. GLOBAL K_GM IS K_MM*1000.

// Types of anomalies.
GLOBAL KA_MEAN IS 0.
GLOBAL KA_ECC IS 1. GLOBAL KA_ECCENTRIC IS KA_ECC.
GLOBAL KA_TRUE IS 2.

// Return t if c else f.
FUNCTION IIF { PARAMETER c. PARAMETER t. PARAMETER f. IF c { RETURN t. } RETURN f. }

// Clamp angles to 0..360 or -180 to 180.  Requires v >= -360.
FUNCTION Clamp360 { PARAMETER v. RETURN MOD(v+360,360). }
FUNCTION Clamp180 { PARAMETER v. RETURN MOD(v+540,360)-180. }

// Adds two-argument versions of arccos/arcsin that return negative values when needed.
{
	LOCAL FUNCTION fn {
		PARAMETER f.
		PARAMETER x.
		PARAMETER y IS 0.
		IF y >= 0 { RETURN f(x). }
		RETURN 360-f(x).
	}
	GLOBAL ASIN IS fn@:bind(arcsin@).
	GLOBAL ACOS IS fn@:bind(arccos@).
}

// kOS doesn't have any good methods for constructing our own timespan.  Fakery.
GLOBAL K_EPOCH IS TIME-TIME.

// Coerce timespan to seconds or vice versa.  If input is already correct time, return it unchanged.
FUNCTION ToTime { PARAMETER t. IF t:IsType("Timespan") { RETURN t. } RETURN K_EPOCH+t. }
FUNCTION ToSeconds { PARAMETER t. IF t:IsType("Timespan") { RETURN t:seconds. } RETURN t. }

// Relative position
// Orbit or orbitable.
FUNCTION RELPOSITION { PARAMETER s. RETURN s:position - s:body:position. }
// Orbitable only.
FUNCTION RELPOSITIONAT { PARAMETER s. PARAMETER t. RETURN POSITIONAT(s,t)-POSITIONAT(ORBITAT(s,t):body,t). }

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
