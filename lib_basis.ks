// Functions for dealing with coordinate axes.
// A basis is a list of 3 normalized vectors that determine the components of other vectors/coordinates.

RUN ONCE lib_util.

// Constants.
GLOBAL K_X is V(1,0,0).
GLOBAL K_Y IS V(0,1,0).
GLOBAL K_Z IS V(0,0,1).

GLOBAL KB_X IS 0.
GLOBAL KB_Y IS 1.
GLOBAL KB_Z IS 2.
// For example, the standard XYZ basis is...
GLOBAL basis_xyz IS LIST(K_X, K_Y, K_Z).

// Maneuvers in KSP use a different coordinate system of (radial, normal, prograde).  This ordering is chosen because it aligns with the parameter order of NODE().
// These functions determine the basis of that coordinate system.

GLOBAL KB_RADIAL IS 0.
GLOBAL KB_NORMAL IS 1.
GLOBAL KB_PROGRADE IS 2.

GLOBAL KB_UP IS 0.
GLOBAL KB_NORTH IS 1.
GLOBAL KB_EAST IS 2.

{
	LOCAL FUNCTION _wrap {
		// Returns maneuver basis -- either for velocity and position vectors, or for an orbital at a time.
		PARAMETER f.
		PARAMETER s IS ship. // or r
		PARAMETER t IS time. // or v
		IF s:IsType("Orbitable") {
			SET t TO ToTime(t).
			RETURN f(RELPOSITIONAT(s, t), VELOCITYAT(s, t):orbit).
		}
		IF s:IsType("Lexicon") {
			SET t TO ToTime(t).
			RETURN f(s["r"], s["v"]).
		}
		RETURN f(s,t).
	}
	LOCAL FUNCTION _mvr {
		PARAMETER r.
		PARAMETER v.
		RETURN List(
			(v + angleaxis(90, VCRS(v,r))):normalized,  // Radial
			VCRS(v,r):normalized, // Normal
			v:normalized  // Prograde
		).
	}
	LOCAL FUNCTION _une {
		PARAMETER r.
		PARAMETER v.
		LOCAL n IS VXCL(r, K_Y-r).
		RETURN LIST(r:normalized,n:normalized,VCRS(r,n):normalized).
	}
	GLOBAL basis_mvr IS _wrap@:bind(_mvr@).
	GLOBAL basis_une IS _wrap@:bind(_une@).
}



// 'Inverts' a basis: returns a new basis such that basis_transform(new, basis_transform(old, vec)) == vec.
FUNCTION basis_invert {
	PARAMETER b.  // Basis.
	RETURN LIST(
		V(b[0]:x, b[1]:x, b[2]:x),
		V(b[0]:y, b[1]:y, b[2]:y),
		V(b[0]:z, b[1]:z, b[2]:z)
	).
}
		
// Transform XYZ vector to new basis (or back).
FUNCTION basis_transform {
	PARAMETER b.  // Basis.
	PARAMETER vec.  // Vector.
	PARAMETER invert IS FALSE.
	IF invert { SET b TO basis_invert(b). }
	RETURN V(vec*b[0],vec*b[1],vec*b[2]).
}

// Converts a node to a radial/normal/prograde vector.
FUNCTION node_to_vector {
	PARAMETER n.
	RETURN V(n:radialout, n:normal, n:prograde).
}

// Converts a radial/normal/prograde vector to a node.
FUNCTION vector_to_node {
	PARAMETER v.
	PARAMETER t IS TIME.
	RETURN NODE(t,v:x,v:y,v:z).
}
