# ksp-kos-scripts
Scripts for kOS, a mod for Kerbal Space Program

## anomaly_data
`lib_orbit.ks` contains functions for calculating Eccentric Anomaly, which is a complicated process.  To help narrow
down its search, `anomaly_data.ksm` can be used to provide it with good starting guesses.
 
`anomaly_data.py` can be used with Python 3 to produce `anomaly_data.ks`, which can then be compiled to 
`anomaly_data.ksm`.

NOTE: kOS takes an **exceedingly** large amount of time to compile anomaly_data.ksm, and KSP will appear crashed while
it is compiling.  A precompiled version is included for your convenience, *though you may want to compile it yourself
and not run .ksm files from internet strangers who might do cute things like delete your archive files.*

It's highly recommended you don't attempt to run the uncompiled version directly because of the amount of parsing time 
kOS needs to run it.  (The compiled version has almost no impact on startup time.)

## kinstall
Kinstall is a source code minifier and installer for KerbalScript files, written in... Kerbalscript.  See its README 
file for details.

## lib_util.ks
Misc utility functions and constants used by other libraries:

- K_PI (same as constant():pi but shorter) and K_DEGREES (180/pi) constants.  
  Divide by K_DEGREES to convert degrees to radians, multiply to convert from radians to degrees.
  
- IIF(condition, value_if_true, value_if_false)

- Clamp360 (reduces an angle down to fit within 0..360) and Clamp180 (within -180..180) functions.

- ASIN and ACOS, which are the same as ARCSIN and ARCCOS but take an optional second parameter.  If the second 
  parameter is negative, the result is (360-result).

## lib_orbit.ks
Contains functions for working with Orbit Lexicons (`orb`s), which are similar to the `Orbit` structure but contain
additional data and can be manipulated in various ways.  Also contains a function for calculating Eccentric Anomaly
from Mean Anomaly, optionally with a precalculated table named `eccentric_anomaly_table` (see notes on `anomaly_data`)

An `orb` is time aware.  Its epoch can be changed with `orb_set_time()`, which will adjust its various anomaly 
attributes and its position and velocity vectors to reflect its predicted position at the new time.
  
`orb`s can be constructed from an existing orbit using `orb_from_orbit(orbit_or_orbitable=obt, t=time)`.  They
can also be constructed from position and velocity vectors using 
`orb_from_vectors(r=obt:position-body:position, v=obt:velocity:orbit, b=body, t=time)`.  (Default parameters are shown)

`orb_from_vectors()` can be useful to predict the results of one or more maneuvers without actually creating maneuver 
nodes.  This can be useful for certain maneuvers, e.g. to see if a 3-burn inclination change (raise apoapsis, inc burn,
lower apoapsis) is more efficient than a single burn, or to see if a bi-elliptic transfer is more efficient than a 
Hohmann one.  Note that due to floating point math, there is significant loss in precison.

## lib_basis.ks
Adds functions for converting between 
[coordinate bases](https://en.wikipedia.org/wiki/Basis_(linear_algebra)#Ordered_bases_and_coordinates), including 
converting a XYZ vector to terms of (radial, normal, prograde) for plotting maneuvers or to terms of (Up, North, East)
for various calculations.

## lib_axisdraw.ks
Adds a simple mechanism that draws the X, Y, Z, Normal, Prograde and Radial vectors on screen.

## lib_maneuver.ks
Super early and probably buggy attempt to implement maneuver planning (ala Mechjeb) in KS.
