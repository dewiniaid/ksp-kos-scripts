// Functions for dealing with coordinate axes.
// A basis is a list of 3 normalized vectors that determine the components of other vectors/coordinates.  For example, the standard XYZ basis is...
GLOBAL basis_xyz IS LIST(V(1,0,0), V(0,1,0), V(0,0,1)).

// Maneuvers in KSP use a different coordinate system of (radial, normal, prograde).  This ordering is chosen because it aligns with the parameter order of NODE().
// These functions determine the basis of that coordinate system.

// Returns maneuver basis given velocity and radius vectors
FUNCTION basis_for_vr {
	PARAMETER v.
	PARAMETER r.
	RETURN List(
		(v + angleaxis(90, VCRS(v,r))):normalized,  // Radial
		VCRS(v,r):normalized, // Normal
		v:normalized  // Prograde
	).
}

// Returns maneuver basis for ship (or any orbitable)
FUNCTION basis_for_ship {
	PARAMETER ship IS ship.
	PARAMETER t IS time.
	RETURN basis_for_vr(VELOCITYAT(ship, t):orbit, POSITIONAT(ship, t)-POSITIONAT(ship:body, t)).
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
