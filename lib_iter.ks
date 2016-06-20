@LAZYGLOBAL OFF.
// Iterator functions.

// Calls fn(item) for each element in iterable.  Returns nothing.
FUNCTION iter_call {
	PARAMETER fn.
	PARAMETER iterable.
	FOR item IN iterable { fn(item). }
}

// If iterable is a list, updates the list to contain the results of fn(item) for each item in the list and returns the list..
// If iterable is a lexicon, updates each value (not key) to contain the results of fn(value) and returns the lexicon.
FUNCTION iter_map {
	PARAMETER fn.
	PARAMETER iterable.
	
	LOCAL keys IS FALSE.
	IF iterable:istype("Lexicon") {
		SET keys TO iterable:keys.
	} ELSE {
		SET keys TO RANGE(iterable:length).
	}
	FOR k IN keys { SET iterable[k] TO fn(iterable[k]). }
	RETURN iterable.
}

// Reduces an iterable to a single value by calling fn(a,b) repeatedly, where:
// - The first call of fn(a,b) uses the first and second elements of the iterable.
// - Subsequent calls use the return value of the previous call as 'a' and the next item in the iterable as 'b'.
// If the iterable contains only one element, it is returned directly.
// If the iterable is empty, returns False.

FUNCTION iter_reduce {
	PARAMETER fn.
	PARAMETER iterable.
	LOCAL last IS FALSE.
	LOCAL init IS FALSE.
	FOR item IN iterable {
		IF NOT init {
			SET last TO item.
			SET init TO true.
		} ELSE {
			SET last TO fn(last, item).
		}
	}
	RETURN last.
}

GLOBAL iter_min IS iter_reduce@:bind(min@).
GLOBAL iter_max IS iter_reduce@:bind(max@).

// iter_nearest and iter_furthest return the value in the iterable that is 'nearest' or 'furthest' to the target value, where distance is defined as ABS(value - item).
// If two or more items tie, any one of them may be returned.
// If being called as iter_nearest and an item's distance is 0, it is immediately returned.
FUNCTION iter_distdir {
	PARAMETER dir. // -1 is nearest, 1 is furthest.
	PARAMETER value.
	PARAMETER iterable.

	LOCAL winner IS FALSE.
	LOCAL highscore IS FALSE.
	LOCAL init IS FALSE.
	FOR item IN iterable {
		LOCAL score IS dir*ABS(value - item).
		IF NOT init OR score>highscore {
			IF dir=-1 AND score=0 { RETURN item. }
			SET winner TO item.
			SET highscore TO score.
			SET init TO true.
		}
	}
	RETURN winner.
}
GLOBAL iter_nearest  IS iter_distdir@:bind(-1).
GLOBAL iter_furthest IS iter_distdir@:bind(1).
