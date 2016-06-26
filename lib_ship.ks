// Vessel utility functions.

// Return lexicon of all vessels..
FUNCTION Ship_Lexicon {
	PARAMETER includeSelf IS TRUE.	// FALSE = don't include ourself in the lexicon.
	LOCAL v IS LIST().
	LOCAL rv IS LEXICON().
	LIST targets IN v.
	IF includeSelf { targets:add(ship). }
	FOR vessel IN v {
		IF rv:haskey(vessel:name) {
			rv[vessel:name]:add(vessel).
		} ELSE {
			SET rv[vessel:name] TO LIST(vessel).
		}
	}
	RETURN rv.
}

FUNCTION Ship_Engines {
	// Returns list of engines.
	PARAMETER ship.
	LOCAL result IS LIST().
	//Disabled due to kOS bug #1683 - https://github.com/KSP-KOS/KOS/issues/1683
	//LIST engines FROM ship IN result.  
	LIST engines IN result.
	RETURN result.
}

FUNCTION Ship_ActiveEngines {
	// Returns list of all active engines 
	PARAMETER ship IS ship.
	PARAMETER includeFlameOut IS FALSE.
	LOCAL result IS LIST().
	FOR engine IN Ship_Engines(ship) {
		IF engine:ignition AND (includeFlameOut OR NOT engine:flameout) {
			result:add(engine).
		}
	}
	RETURN result.
}

FUNCTION Ship_AverageISP {
	// Returns current average ISP.
	PARAMETER ship IS ship.
	PARAMETER activeOnly IS TRUE.
	PARAMETER includeFlameOut IS FALSE.
	LOCAL engines IS 0.
	IF activeonly { SET engines TO Ship_ActiveEngines(ship, includeFlameOut). }
	ELSE { SET engines TO Ship_Engines(ship). }
	
	LOCAL n IS 0.
	LOCAL d IS 0.
	
	FOR engine IN engines {
		SET n TO n+engine:availablethrust.
		SET d TO d+(engine:availablethrust / engine:isp).
	}
	RETURN n/d.
}

