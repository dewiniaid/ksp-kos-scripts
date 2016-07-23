# kinstall

## What is it?

kinstall is a hybrid source code minifier and installer for KerbalScript files.  It is itself written in Kerbalscript... which is a bit ridiculous, but that's half the fun.

It serves two purposes:

- Transfer your source code file and all of its dependencies intelligently.
- Reduce the size of the transfered code by stripping out comments and extraneous whitespace without altering your originals.

## How do I use it?

At the most basic level:
```
RUN ONCE kinstall.
kinstall(FILE).
```
Will find FILE on the archive, locate its dependencies, minify everything, and transfer it all to the volume associated with the currently running processor (i.e. `core:volume`, *not* `core:currentvolume`)

More detailed documentation (including a myriad of options) is the remainder of this documentation.

## Detailed `kinstall` usage.

File: `kinstall.ks`

`kinstall(FILE, DEST, SOURCE, CFG)`

parameter | default | meaning
--------- | ------- | -------
`FILE` | *required* | The filename to install.
`DEST` | `core:volume` | The destination volume.
`SOURCE` | `archive` | The source volume (which should contain FILE).  Will also be used for temporary files if the configuration doesn't specify otherwise.
`CFG` | `KINSTALL_CONFIG` | A Lexicon of configuration options to use.

When passing CFG to `kinstall`, it is only neccessary to specify options differing from the defaults specified in KINSTALL_CONFIG.



## KINSTALL_CONFIG

File: `lib_kinstall.ks`

`lib_kinstall.ks` contains a lexicon entitled KINSTALL_CONFIG, which specifies most of the default configuration options used by the kinstall functions:

### General options.

Name | Type | Description
---- | ---- | -----------
recurse | bool | **Always enabled in this build** Whether `kinstall` should look through additional scripts.  The current build always looks through additional scripts.
fileref | bool | **Not Yet Implemented** If enabled, a comment of the format //@ref FILENAME will include that file in the install process as a (non-optimized) dependency.  
inplace | bool | When kinstall compiles scripts, it normally compiles them to a temporary filename rather than accepting the defaults to avoid overwriting data on the source.  This tells kinstall to instead compile scripts using the default filename, and not to delete the compiled versions from the source.
rewrite | bool | **Always enabled in this build** Whether kinstall should rewrite statements of the form `RUN script.ks.` to `RUN script.`  This build always rewrites statements, which is good because otherwise your code can't refer to the compiled version even if the installer determines that it is smaller.  
ksm_as_ks | bool | **Not yet implemented** Whether the installer is allowed to give a compiled file a `.ks` extension.  Neccessary if code refers to `foo.ks`, rewrite is disabled and `foo.ksm` happens to be smaller.
ks_as_ksm | bool | **Not yet implemented** Whether the installer is allowed to give a script file a `.ksm` extension.  Neccessary if code refers to `foo.ks`, rewrite is disabled and `foo.ksm` happens to be smaller.
ipu | int | If nonzero, temporarily set config:IPU to this value during the install and then back afterwards.  Some of what `kinstall` does is very expensive (parsing other scripts), so this helps speed that along.  Note that kOS lacks any proper exception handling, so if kinstall fails (possibly due to a syntax error in one of the compiled scripts), the IPU value will *not* be restored.
compile | bool | Whether `kinstall` should try compiling your code to see if it yields a smaller filesize.
minify | bool | Attempts to reduce source code size.  If `false`, none of the Minify options are processed.

### Minify options

For numeric options, a value of -1 is equal to whatever the current maximum value is.

Name | Type | Description
---- | ---- | -----------
comments | bool | Requires minify.  If `true`, strip comments from code.
lines | int | How to handle linebreaks.   Note that options other than 0 will cause kOS to claim the wrong line of code if an error occurs.
 | | 0: Do nothing.
 | | 1: Remove blank lines (including those with just whitespace or a stripped comment)
 | | 2: Collapse lines to 0 or 1 space when possible.  Requires space=2+ to function correctly.
space | int | How to handle whitespace (space, tab, etc.)
 | | 0: Do nothing.
 | | 1: Strip leading/trailing whitespace
 | | 2: ... and also leading whitespace in comments.  (Same as 1 if comments are stripped.)
 | | 3: ... and reduce multiple whitespace characters to a single space.
 | | 4: Remove all space except the bare minimum to allow correct program interpretation.

### Miscellaneous Options


Name | Type | Description
---- | ---- | -----------
sanity | bool | `kinstall` tries hard to avoid screwing up real data on the Archive: you can't target it as the destination for an install, and it will yell loudly if something would cause it to try to overwrite anything on it (other than temporary filenames containing "_kinstall.X", where X is the`time:seconds` at the start of the script).  Setting sanity to `false` disables these checks.
cleanup | bool | If `true` (the default), `kinstall` removes its temporary files when it is done using them.
tempvol | VOLUME | If this key exists, it defines the temporary volume that `kinstall` will use during its install process.  This normally defaults to your install source, generally the archive.

## KINSTALL_PARSE

File: `kinstall_parse.ks`

`kinstall_parse` does the heavy lifting of minifying source code and finding dependencies.  It also returns a Lexicon containing detailed parse data that you may be able to analyze from within another script.

`kinstall(FILE, VOL, MINIFY, MINIFY_COMMENTS, MINIFY_LINES, MINIFY_SPACE)`

parameter | default | meaning
--------- | ------- | ---------
`FILE` | *required* | The filename to parse.
`VOL` | `core:currentvolume` | Volume containing the file.
`MINIFY` | `FALSE` | Whether to minify the source code.
`MINIFY_COMMENTS` | `KINSTALL_CONFIG["comments"]` | See `KINSTALL_CONFIG`.  Ignored if MINIFY=FALSE
`MINIFY_LINES` | `KINSTALL_CONFIG["lines"]` | See `KINSTALL_CONFIG`.  Ignored if MINIFY=FALSE
`MINIFY_SPACE` | `KINSTALL_CONFIG["space"]` | See `KINSTALL_CONFIG`.  Ignored if MINIFY=FALSE

### Return value

`kinstall_parse` returns a Lexicon of data it finds during the parse.  The Lexicon has the following keys:

key | type | Explanation
--- | ---- | ------------
`run` | LIST() | Contains information on found RUN statements; used for dependency solving.  LIST of LISTs.  Each inner list is in the format (`index`, `is_once`, `filename`).
'ref' | LIST() | **Not yet implemented** List of `//@ref` references.  See `KINSTALL_CONFIG`.
'ops' | LIST() of strings | List of operations/token types in the parse data.  Corresponds 1 to 1 with the items in `data`.
'data' | LIST() of strings | Data corresponding to each operation.   `result["data"]:join("")` yields the (possibly minified) file contents.

### Meanings of ops ###

op/token | contents of `data[ix]`
-------- | -------
STR | A quoted string literal, or part of one.  Multiline strings may not have both quotation marks in data.
SP | Whitespace character(s)
COM | Comments, including the opening `//`.
EOS | End-of-statement indicator.  (A single period).
NUM | A number.
SYM | A "symbol", such as a function name, variable name or bareword filename, 
BRACE | One of `{}[]()`, indicating a change of scope/etc.
OP | An operator (such as `+` or `<>`).  Note that `:` and `#` are treated as operators.
AT | `@`, probably immediately followed by a SYM of "lazy_globals".



