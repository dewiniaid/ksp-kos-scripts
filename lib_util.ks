// Utility functions and constants.
GLOBAL K_PI IS constant():pi.  // Shorter!
// Divide to convert degrees to radians, multiply to convert radians to degrees.
GLOBAL K_DEGREES IS 180/K_PI.

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
