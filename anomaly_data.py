"""
Generates a table of solutions for eccentric anomaly.  Intended as a starting convergence point for more specific
solvers, e.g. KerboScript code.

Basic usage:
anomaly_data.py -K anomaly_data.ks -C anomaly_data.csv

NOTE: kOS takes an inordinately long amount of time to parse KS files that this utility creates, and Kerbal Space
Program will appear to be locked up during the parse.  It is STRONGLY recommended that you do the following:
1. COMPILE the resulting file.
2. Grab your beverage of choice.
3. Don't panic that KSP still looks like it is locked up.
4. Browse the internet for a few minutes.
5. Wait some more.
6. Use the compiled .ksm file in the future, rather than the .ks file.

See anomaly_data.py --help for more detailed usage instructions.
"""
import argparse
import sys
import math
import functools
import itertools
import csv
import io

# Multiplying by this value converts radians to degrees.
DEGREES = 180/math.pi

eprint = functools.partial(print, file=sys.stderr)

parser = argparse.ArgumentParser(
    description="Generates tables of mean-to-eccentric anomaly conversions."
)
group = parser.add_argument_group(
    title="Calculation options",
    description=(
        "Where e=eccentricity, E=eccentric anomaly, and M=mean anomaly:"
        "\n"
        "Eccentricity steps correspond to e=1/x, e=2/x... e=x/x.  e=0 is not output by default since E=M in that case."
        "\n"
        "Anomaly steps correspond to M=1/x*180 degrees.. M=x/x*180 degrees.  M=0 is not output by default since E=M in"
        " that case.  (It's also true for M=180)"
        "Anomaly values for M > 180 are not output and can be derived as: 360 - f(360-M)."
    )
)
group.add_argument(
    "-e", "--ecc-steps", metavar="STEPS",
    help="Number of eccentricity steps to include in the table.  (Default: 10)",
    default=10, type=int
)
group.add_argument(
    "-a", "--anomaly-steps", metavar="STEPS",
    help="Number of mean anomaly steps to include in the table.  (Default: 180)",
    default=180, type=int
)
group.add_argument(
    "--min", default=10, type=int,
    help="Perform a minimum of X refinement passes per anomaly, even if the accuracy threshold is met.  (Default: 15,"
         "corresponding to 1E-15)"
)
group.add_argument(
    "--max", help="Perform a maximum of X refinement passes per anomaly.",
    default=100, type=int
)
group.add_argument(
    "--accuracy", help="Stop when result is within 10^-X Perform a maximum of X refinement passes per anomaly.",
    default=15, type=int
)
group.add_argument(
    "-z", "--zero", help="Include table entries for e=0 and for M=0 even though E=M in these cases.",
    action="store_true"
)
group = parser.add_argument_group(title="Options affecting CSV output.")
group.add_argument(
    "-C", "--csv", metavar="CSVFILE", type=argparse.FileType("w"),
    help=(
        "Write resulting tables to named CSV file.  By default, has one row per eccentricity value; to have one row per"
        "anomaly instead see -X"
    )
)
group.add_argument(
    "-X", "--transpose", action="store_true",
    help="Transpose rows and columns in the CSV file: write one row per anomaly rather than one per eccentricity."
)
group = group.add_mutually_exclusive_group()
group.add_argument(
    "--no-headers", action="store_false", dest="headers",
    help="Do not include eccentricity/anomaly values in the first row/column of the CSV output."

)
group.add_argument(
    "--headers", action="store_true", dest="headers", default=True,
    help="Include eccentricity/anomaly values in the first row/column of the CSV output.  (Default)",
)
group = parser.add_argument_group(title="Options affecting KerboScript output.")
group.add_argument(
    "-K", "--ks", "--kerboscript", type=argparse.FileType("w"),
    help="Write results to specified KerboScript file."
)
group.add_argument(
    "--name", metavar="NAME", dest="variable_name", type=str, default="eccentric_anomaly_table",
    help="Name the list variable NAME.  (Default: eccentric_anomaly_table)"
)
group = group.add_mutually_exclusive_group()
group.add_argument(
    "--no-minify", action="store_false", dest="minify",
    help="Do not minify KS output."

)
group.add_argument(
    "--minify", action="store_true", dest="minify", default=True,
    help="Minify KS output.  This is the default"
)

opts = parser.parse_args()
if opts.csv is None and opts.ks is None:
    eprint("At least one of --csv or --kerboscript must be specified.")
    parser.print_help(file=sys.stderr)
    sys.exit(2)
if opts.ecc_steps < 1: parser.error("Eccentricity steps must be > 0")
if opts.anomaly_steps < 1: parser.error("Anomaly steps must be > 0")
if opts.min < 0: parser.error("Minimum refinement steps must be >= 0")
if opts.max < opts.min: parser.error("Maximum refinement steps cannot be less than the minimum")
if opts.accuracy < 0: parser.error("Accuracy must be at least 0")

opts.accuracy = 10**-opts.accuracy

# eprint(repr(opts))
# eprint(dir(opts.csv))

maximum_steps_used = 0
total_steps_used = 0
total_calculations = 0

def eccentric_anomaly(ecc, mean, guess=None):
    """
    Calculates eccentric anomaly, in degrees.

    :param ecc: Eccentricity (e).
    :param mean: Mean Anomaly (M) in degrees.
    :param guess: Starting guess.
    :return: Calculated anomaly in degrees.
    """
    global maximum_steps_used, total_steps_used, total_calculations
    mean %= 360
    if not ecc or mean == 0 or mean == 180:
        return mean  # E=M in all cases of this.
    if mean > 180:
        return 360 - eccentric_anomaly(ecc, 360-mean, None if guess is None else 360-guess)

    total_calculations += 1

    # Convert to radians
    mean /= DEGREES
    guess = mean if guess is None else guess/DEGREES

    # fmt = "e:[{ecc:.2f}] M:[{mean:6.2f}] guess:[{guess:9.4f}] err:[{err:9.4f}]"

    # Initial result.
    maxguess = 180
    minguess = mean
    err = (guess - ecc*math.sin(guess)) - mean
    # print(("-" * len(str(maximum_steps))) + "- " + fmt.format(ecc=ecc,mean=mean,guess=guess,err=err))
    # fmt = "{step:" + str(len(str(maximum_steps))) + "}: " + fmt

    # Refine result.
    for step in range(opts.max):
        maximum_steps_used = max(step, maximum_steps_used)
        total_steps_used += 1

        if err > 0:  # Guessed too high.
            maxguess = guess
            guess = (guess+minguess)/2
        else:  # Guessed too low.
            minguess = guess
            guess = (guess+maxguess)/2
        err = (guess - ecc * math.sin(guess)) - mean
        # print(fmt.format(step=step, ecc=ecc, mean=mean, guess=guess, err=err))

        if step >= opts.min and abs(err) < opts.accuracy:
            return guess*DEGREES

    # Max iterations!
    return guess*DEGREES


def frange(steps, maxval=1):
    """Yields 0, maxval, and step/maxval for steps between 1 and steps"""
    for step in range(steps):
        if opts.zero or step:
            yield (step/steps) * maxval
    yield maxval  # We could do range(steps+1), but this avoids any possible floating point error.

anomaly_range = functools.partial(frange, opts.anomaly_steps, 180)
ecc_range = functools.partial(frange, opts.ecc_steps, 1)

eprint("")
results = list()
for ecc in ecc_range():
    eprint("\rCalculating ecc={:.4f}...  ".format(ecc), end="")
    results.append(list(eccentric_anomaly(ecc, mean) for mean in anomaly_range()))

eprint("")
eprint("Total calculations: {}".format(total_calculations))
eprint("Total steps:        {}".format(total_steps_used))
eprint("Maximum steps used: {}".format(maximum_steps_used))
eprint("Average steps used: {}".format(total_steps_used/total_calculations))

if opts.csv:
    eprint("Writing CSV file.")
    csv_results = results
    if opts.transpose:
        csv_results = zip(*csv_results)
        rrange = anomaly_range
        crange = ecc_range
    else:
        crange = anomaly_range
        rrange = ecc_range
    # argparse.FileType doesn't let us set newlines='' when it opens a file, and sys.stdout is already open.
    # We make our own iowrapper to work around this.
    opts.csv.flush()
    with io.TextIOWrapper(opts.csv.buffer, newline='') as f:
        writer = csv.writer(f)
        if not opts.headers:
            for row in csv_results: writer.writerow(row)
        else:
            writer.writerow(
                itertools.chain(
                    ["M / e" if opts.transpose else "e / M"],
                    crange()
                )
            )
            for value, data in zip(rrange(), csv_results):
                writer.writerow(itertools.chain([value], data))
        f.flush()


def _gen(items, prefix="", suffix="", sep="", nested=False, format=None):
    def _fmt(x):
        if format:
            return x.format(**format)
        return x

    first = True
    for item in items:
        if first:
            first = False
        else:
            yield _fmt(sep)
        yield _fmt(prefix)
        if nested:
            yield from item
        else:
            yield item
        yield _fmt(suffix)

if opts.ks:
    f = opts.ks
    eprint("Writing KS file.")
    # variable = LIST(  LIST  (       a       ,      b,c,d)      ,      LIST(...) )
    # [prefix          ][r_pre][c_pre] [c_suf][c_sep].....[r_suf][r_sep]        [suffix]
    prefix = "GLOBAL {} IS LIST(\n".format(opts.variable_name)
    suffix = "\n).\n"
    r_pre = "\tLIST("
    r_suf = ")"
    r_sep = ",\n"
    c_pre = ""
    c_suf = ""
    c_sep = ", "
    ecc = 0
    if opts.minify:
        prefix = prefix.strip()
        suffix = suffix.lstrip()
        r_pre = r_pre.strip()
        r_suf = r_suf.strip()
        r_sep = r_sep.strip()
        c_pre = c_pre.strip()
        c_suf = c_suf.strip()
        c_sep = c_sep.strip()

    f.write(prefix)

    for chunk in _gen(
            (_gen(line, c_pre, c_suf, c_sep) for line in results),
            r_pre, r_suf, r_sep, nested=True
    ):
        f.write(str(chunk))
    f.write(suffix)
