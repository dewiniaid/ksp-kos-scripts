// Functions for dealing with coordinate axes.
// A basis is a list of 3 normalized vectors that determine the components of other vectors/coordinates.  For example, the standard XYZ basis is...
GLOBAL basis_xyz IS LIST(V(1,0,0), V(0,1,0), V(0,0,1)).

// Maneuvers in KSP use a different coordinate system of (radial, normal, prograde).  This ordering is chosen because it aligns with the parameter order of NODE().
// These functions determine the basis of that coordinate system.

// Returns maneuver basis given velocity and position vectors
FUNCTION basis_mvr {
	PARAMETER v.
	PARAMETER r.
	RETURN List(
		(v + angleaxis(90, VCRS(v,r))):normalized,  // Radial
		VCRS(v,r):normalized, // Normal
		v:normalized  // Prograde
	).
}

// Returns maneuver basis for ship (or any orbitable)
FUNCTION basis_mvr_for {
	PARAMETER ship IS ship.
	PARAMETER t IS time.
	RETURN basis_mvr(VELOCITYAT(ship, t):orbit, POSITIONAT(ship, t)-POSITIONAT(ORBITAT(ship, t):body, t)).
}

// Returns up-north-east basis given velocity and position vectors
FUNCTION basis_une {
	PARAMETER v.
	PARAMETER r.
	LOCAL n IS VXCL(r, V(0,1,0)-r).
	LOCAL e IS VCRS(r, n).
	RETURN LIST(r:normalized,n:normalized,e:normalized).
}

// Returns up-north-east basis for ship (or any orbitable)
FUNCTION basis_une_for {
	PARAMETER ship IS ship.
	PARAMETER t IS time.
	LOCAL v IS VELOCITYAT(ship, t).
	LOCAL r IS POSITIONAT(ship, t)-POSITIONAT(ORBITAT(ship, t):body, t).
	RETURN basis_une(v, r).
}

// Returns up-north-east basis for ship (or any orbitable)
FUNCTION basis_une_for_old {
	PARAMETER ship IS ship.
	PARAMETER t IS time.
	LOCAL v IS VELOCITYAT(ship, t).
	LOCAL b IS ORBITAT(ship, t):body.
	LOCAL r IS POSITIONAT(ship, t)-POSITIONAT(b, t).
	LOCAL u IS r:normalized.
	LOCAL n IS VXCL(u, (V(0,1,0) * b:radius) - r):normalized.
	LOCAL e IS VCRS(u, n).
	RETURN LIST(u,n,e).
}

// 'Inverts' a basis: returns a new basis such that basis_transform(new, basis_transform(old, vec)) == vec.
FUNCTION inverse_basis {
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
	IF invert { SET b TO inverse_basis(b). }
	RETURN V(vec*b[0],vec*b[1],vec*b[2]).
}

