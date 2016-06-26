@LAZYGLOBAL OFF.
// RemoteTech supports.
RUN ONCE lib_util.

FUNCTION RT_ToggleAntennas {
	PARAMETER active IS -1.  // -1: Toggle all.  0/False: Deactivate all.  1/True: Activate all.
	SET active TO IIF(IsFalse(active), 0, IIF(IsTrue(active), 1, active)).
	
	FOR module IN ship:modulesNamed("ModuleRTAntenna") {
		IF active<>0 AND module:HasEvent("Activate") {
			module:doEvent("Activate").
		} ELSE IF active<>1 AND module:HasEvent("Deactivate") {
			module:doEvent("Deactivate").
		}
	}
}

// Given a circular orbit, an antenna range and a set number of satellites, returns the maximum radius of the orbit such that each satellite can reach the next satellite in the sequence.
// Or: Given a regular "numsats"-sided polygon with side "antennarange", return the circumradius.
// With a regular polygon of 
FUNCTION RT_MaxRadius {
	PARAMETER antennarange.
	PARAMETER numsats.
	
	RETURN antennarange/SIN(180/numsats)/2.
}
