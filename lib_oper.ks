// Mathematical operators as functions.
// Useful for places that accept delegates.
FUNCTION oper_add { PARAMETER a. PARAMETER b. RETURN a+b. }
FUNCTION oper_subtract { PARAMETER a. PARAMETER b. RETURN a-b. }
FUNCTION oper_minus { PARAMETER a. RETURN -a. }
FUNCTION oper_multiply { PARAMETER a. PARAMETER b. RETURN a*b. }
FUNCTION oper_divide { PARAMETER a. PARAMETER b. RETURN a/b. }
FUNCTION oper_pow { PARAMETER a. PARAMETER b. RETURN a^b. }
FUNCTION oper_and { PARAMETER a. PARAMETER b. RETURN a AND b. }
FUNCTION oper_or { PARAMETER a. PARAMETER b. RETURN a OR b. }
FUNCTION oper_not { PARAMETER a. RETURN NOT a. }
FUNCTION oper_eq { PARAMETER a. PARAMETER b. RETURN a=b. }
FUNCTION oper_ne { PARAMETER a. PARAMETER b. RETURN a<>b. }
FUNCTION oper_lt { PARAMETER a. PARAMETER b. RETURN a<b. }
FUNCTION oper_le { PARAMETER a. PARAMETER b. RETURN a<=b. }
FUNCTION oper_gt { PARAMETER a. PARAMETER b. RETURN a>b. }
FUNCTION oper_ge { PARAMETER a. PARAMETER b. RETURN a>=b. }
