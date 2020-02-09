# lua-turtle

`lua-turtle` is an implementation of
[TurtleScript](https://github.com/cscott/turtlescript) in
Lua.  TurtleScript is a syntactic
(but not semantic) subset of JavaScript, originally created for
the One Laptop per Child project.  This implementation especially
takes pains to match the official EcmaScript runtime semantics from
https://tc39.es/ecma262 probably at the expense of exection speed.

## Install, and Run

This installation is standalone, although there is a luarocks spec file
in the repo.

To run a TurtleScript
[REPL](http://en.wikipedia.org/wiki/Read%E2%80%93eval%E2%80%93print_loop):
```
$ bin/luaturtle
>>> 2+3
5
>>> var fact = function(x) { return (x<2) ? x : (x * fact(x-1)) ; };
undefined
>>> fact(42)
1.4050061177529E+51
>>>
```
Use Control-D (or Control-C) to exit the REPL.  You can also evaluate entire
TurtleScript scripts by passing the name on the command line:
```
$ bin/luaturtle foo.js
```

## Testing
You can run the unit tests with `lua run_tests.lua` from the top-level
directory. See `tests/test_interp.lua` for a set of script-based tests,
which you could manually reproduce in the REPL (if you were so inclined).

## Design
`lua-turtle` is an interpreter for the bytecode emitted by
`bcompile.js` from the TurtleScript project.  It is heavily based on
`binterp.js` from that project, which is a TurtleScript interpreter written
in TurtleScript, as well as on `rusty-turtle` and `php-turtle`, my previous
implementations of TurtleScript runtimes in Rust and PHP, respectively.
The `luaturtle/startup.lua` file contains the bytecode for the
TurtleScript standard library implementation (from `binterp.js`) as
well as the tokenizer, parser, and bytecode compiler itself (emitted
by `write-lua-bytecode.js` in the TurtleScript project).  This allows
the `lua-turtle` REPL to parse and compile the expressions you type
at it into bytecode modules which it can interpret.

Currently bytecode is interpreted; a logical next step would be to
compile directly to Lua code and eliminate the overhead of the
interpretation loop.  The goal of the JavaScript object model implementation
is to try to map JavaScript operations onto Lua operations as nearly
as possible, to keep the generated Lua code as concise as possible.
Currently Lua/JavaScript interoperability is quite good: most operations
on a JS object can be done directly from Lua code using natural Lua syntax.
We do not currently wrap any Lua objects for insertion into the JavaScript
environment, but it would not be too hard to do so given the EcmaScript
standard's support for 'Exotic' objects.

## Future performance improvements

The representation of arrays at present leaves much to be
desired -- they are just objects with keys which are numeric strings.
These should be replaced by "real" Lua arrays.

We probably need to implement fast paths through `[[Get]]` and `[[Set]]`
for the most typical cases: read/write of plain properties (writable,
enumerable, configurable) and "modern method" invocation (reads of
function objects from not writable/not enumerable/not configurable
properties).

Strings are representing using a 'cons' like structure, which preserves
JavaScript's performance expectations related to string concatenation.
Strings are converted to UTF-8 and then prefixed to index into the Lua
backing storage for object slots.  This ensures that 'foo.bar' from
Lua will invoke `__index` from the metatable and not accidentally hit
the backing storage for property `bar`, but it's possible that we could
improve performance by using the UTF-16 strings directly as keys in a
separate backing table.

A standard optimization technique would make use of type information,
perhaps propagated from variable initialization and the types of
arguments when a function is invoked, in order to reduce the amount of
dynamic type dispatch.  A small number of specialized versions of any
given function could be compiled, falling back to the present bytecode
interpreter if the function turns out to be polyvariant.

However, this implementation has turned the dial in the other direction,
boxing all values and heavily using dynamic dispatch to replace explicit
type comparisons with indirect jumps through the metatable.  As such the
benefit of type inference would be limited to replacing the indirect jumps
with direct jumps (removing the indirection through the metatable).  This
may still be useful.

## Future research

I would like to explore multilingual JavaScript using this platform.
There are some thoughts in
[Wikimedia phabricator](https://phabricator.wikimedia.org/T230665);
[Babylscript](http://www.babylscript.com/) also appears very interesting.

## License

TurtleScript and `lua-turtle` are (c) 2020 C. Scott Ananian and
licensed under the terms of the GNU GPL v2.
