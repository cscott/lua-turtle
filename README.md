# lua-turtle

`lua-turtle` is an implementation of
[TurtleScript](https://github.com/cscott/turtlescript) in
Lua.  TurtleScript is a syntactic
(but not semantic) subset of JavaScript, originally created for
the One Laptop per Child project.  This implementation especially
takes pains to match the official ECMAScript runtime semantics from
https://tc39.es/ecma262 -- probably at the expense of some execution
speed.

## Install, and Run

This installation is standalone.  I developed this code using Lua 5.3.3
but it will probably run on later versions of Lua.

It uses the bitwise >> operator, which was introduced in Lua 5.3 and
is not present in earlier versions.

It also uses the 'utf8' standard library module, which was added in Lua
5.3 and is not present in earlier versions.

To run a TurtleScript
[REPL](http://en.wikipedia.org/wiki/Read%E2%80%93eval%E2%80%93print_loop):
```
$ ./repl.lua
>>> 2+3
5
>>> var fact = function(x) { return (x<2) ? x : (x * fact(x-1)) ; };
undefined
>>> fact(42)
7538058755741581312
>>>
```
Use Control-D (or Control-C) to exit the REPL.  You can also evaluate entire
TurtleScript scripts by passing the name on the command line:
```
$ ./repl.lua foo.js
```

## Testing
You can run the unit tests with `./run_tests.lua` from the top-level
directory. See `tests/test_interp.lua` for a set of script-based tests,
which you could manually reproduce in the REPL (if you were so inclined).

## Design
`lua-turtle` is an interpreter for the bytecode emitted by
`bcompile.js` from the TurtleScript project.  It is heavily based on
`binterp.js` from that project, which is a TurtleScript interpreter written
in TurtleScript, as well as on
[`rusty-turtle`](https://github.com/cscott/rusty-turtle) and
[`php-turtle`](https://github.com/cscott/php-turtle), my previous
implementations of TurtleScript runtimes in Rust and PHP, respectively.
The `luaturtle/startup.lua` file contains the bytecode for the
TurtleScript standard library implementation (from `binterp.js`) as
well as the tokenizer, parser, and bytecode compiler itself (emitted
by `write-lua-bytecode.js` in the
[TurtleScript](https://github.com/cscott/TurtleScript)
project).  This allows the `lua-turtle` REPL to parse and compile the
expressions you type at it into bytecode modules which it can interpret.

The JavaScript object model in
[`luaturtle/jsval.lua`](https://github.com/cscott/lua-turtle/blob/master/luaturtle/jsval.lua)
has been implemented in Lua in a way which
tries to make Lua access to and operations on JavaScript objects feel
natural.  Although this is mostly straightforward for (say) arithmetic
operators on numeric types, some performance compromises were
required.  In particular JS properties are renamed and "hidden" in the
Lua object in order to ensure that direct property access in Lua
doesn't hit in the table but instead goes through the `__index`
method.  It's possible we could dial this back a bit and use the
UTF-16 JS field names directly: since this effectively prepends a `\0`
in front of most ASCII field names this would still ensure that
`__index` is used for most natural human accesses.  Arrays would
require special treatment (see below).

We've implemented fast paths through `[[Get]]` and `[[Set]]`
for the most typical cases: read/write of plain properties (writable,
enumerable, configurable) and "modern method" invocation (reads of
function objects from not writable/not enumerable/not configurable
properties).  Plain properties are stored directly in the Lua
table; descriptors are stored for other properties.

We do not currently wrap any Lua objects for insertion into the JavaScript
environment, but it would not be too hard to do so given the ECMAScript
standard's support for "Exotic" and Proxy objects.

Generally we've tried to use dynamic method dispatch through the
metatable as often as possible to replace explicit
type-test-and-branch code.  For example, instead of testing both
arguments to the `BI_ADD` (binary addition) bytecode operation to see
if either is a String (in which case we need to do string
concatenation instead of numerical addition), we dispatch through the
`__add` method in the metatable.  In the common case where the left
hand operand is already a String, this saves a test and we can do the
concatenation directly.  This technique doesn't work quite as well
when the left-hand operation is a Number, since we still have to test
whether the right-hand operation is a String in that case, but we try
to do as many typechecks as possible in this way.

## Future performance improvements

The representation of arrays at present leaves much to be
desired -- they are just objects with keys which are numeric strings.
These should be replaced by "real" Lua arrays, so we can use (presumably
fast) integer access to a native table and not have to convert every
number offset into a string.

Strings are representing using a 'cons' like structure, which
preserves JavaScript's performance expectations related to string
concatenation.  Strings are converted to UTF-8 and then prefixed to
index into the Lua backing storage for object slots.  As mentioned
above, this ensures that `foo.bar` from Lua will invoke `__index` from
the metatable and not accidentally hit the backing storage for
property `bar`, but it's possible that we could improve performance by
using the UTF-16 strings directly as keys.  We don't use `__index`
inside the bytecode interpreter, so this only affects Lua
interoperability.

We probably want to introduce a "integer string" type, to represent
property accesses using numerical indexes.  In the common case that
the receiver was an array, we'd use the integer value directly to
index backing storage, instead of (slow) conversion to a string.
We'd transparently convert back and forth from "integer string" to
"real string" in the corner cases (plain object access using integer
index / array access using a string).  Alternatively we could
break from the ECMAScript standard and allow numbers to be
[Property Keys](https://tc39.es/ecma262/#sec-topropertykey)
(in the language of the spec) and only convert once we'd passed
the possible dispatch to Array's
[`DefineOwnProperty`](https://tc39.es/ecma262/#sec-array-exotic-objects-defineownproperty-p-desc).

Currently bytecode is interpreted; a logical next step would be to
compile directly to Lua code and eliminate the overhead of the
interpretation loop.  We probably want to precede this with some
additional analysis in the TurtleScript compiler.  A first step
would be escape analysis and the introduction of a `PUSH_LOCAL_FRAME`
opcode to complement `PUSH_FRAME`.  The "local frame" would be used
for those variables which don't escape the current function, and wouldn't
be included in the execution context of functions created in its scope.
A simple runtime would treat `PUSH_FRAME` and `PUSH_LOCAL_FRAME` as
identical, but a more advanced runtime would recognize that properties
of the local frame can be stored in registers and don't actually need
to be implemented as `Get`/`Set` on a literal local frame object.

Indicating the borders of the control flow blocks in the bytecode would
also be useful to transform `JMP` and `JMP_UNLESS` into balanced
`if/then/else` blocks.

Values could be represented as a pair of "metatable" and "value" to
avoid redundant `getmetatable(value)` calls during dispatching.
Instead of implementing `BI_ADD` as:
```
prop = jsval.newString('foo')
result = getmetatable(left).__add(left, right, env)
getmetatable(object).Set(env, object, prop, result)
```
we could write:
```
prop_meta, prop = StringMT, jsval.newStringIntern('foo')
result_meta, result = left_meta._add(left_meta, left, right_meta, right, env)
object_meta.Set(env, object_meta, object, prop_meta, prop, result_meta, result)
```
A follow-on optimization would do basic constant/type propagation to further
optimize this to:
```
result_meta, result = NumberMT._add(NumberMT, 5, right_meta, right, env)
ObjectMT.Set(ObjectMT, object, StringMT, jsval.newStringIntern('foo'), result_meta, result)
```
If right_meta is also known to be NumberMT the first line can become:
```
result_meta, result = NumberMT, NumberMT:from(5 + right.value)
```
Finally, we can 'unbox' primitive types when they are stored in registers
and re-box on storage (or when the types become unknown at a merge point)
to get:
```
prop_meta, prop = StringMT, '\0f\0o\0o'
result_meta, result = NumberMT, (5 + right)
object_meta.Set(object_meta, object, StringMT, StringMT:fromUtf16(prop), NumberMT, NumberMT:from(result))
```
Note that `prop_meta` and `result_meta` are constants here and thus
unused (for example, we've just substituted their values in the call
to `object_meta.Set`); I've written assignments for them above just
for clarity.

We may have to introduce explicit
[PHI and SIGMA](https://en.wikipedia.org/wiki/Static_single_assignment_form)
functions in the bytecode to facilitate the representation of the analysis
results to the code generator.

## Future research

I would like to explore multilingual JavaScript using this platform.
There are some thoughts in
[Wikimedia phabricator](https://phabricator.wikimedia.org/T230665);
[Babylscript](http://www.babylscript.com/) also appears very interesting.

For that matter, multilingual Lua might be a better first step, the
Lua language is extremely compact!

NOTES:
In lua, any type can be a table key, but there is syntactic sugar for using
strings as keys:
```
point = { x = 10, y = 20 }   -- Create new table
print(point["x"])            -- Prints 10
print(point.x)               -- Has exactly the same meaning as line above. The easier-to-read dot notation is just syntactic sugar.
```
In Multilinugal lua, the 'sugar' would be internationalized: "symbols"
are the default keys, and the `_("xxx")` constructor makes a symbol out
of a string.
```
point = { _("x") = 10, _("y") = 20 }
print(point[_("x")])            -- Prints 10
print(point.x)               -- Has exactly the same meaning as line above.
```

(Note that `point` is also effectively _("point") as well.)
Two issues:
1. How does _("x") know what the "current language" is?
2. How to disambiguate if foo.x and bar.x are actually translated differently?
(ie `fish.net` vs `ether.net` -- although in spanish these are both `red`.)

In multilingual JS, we had a special import statement and #foo syntax to
mark "symbols" as a separate type.
```
point = { #x = 10, #y = 20 }
print(point[#x])            -- Prints 10
print(point.x)               -- Has exactly the same meaning as line above.
```
(do we need declare #x and point, etc?) (also #foo is already used in lua
for 'length' operator)

Lua has the meta table function __index which could help:
```
__index = function(values, n)
  return values[_(n)]
end
```
-- or maybe this goes the other way, in the sense that __index can be used
to convert from symbols to strings or integer indexes so you can get
fastpath behavior from the lua jit.



## License

TurtleScript and `lua-turtle` are (c) 2020 C. Scott Ananian and
licensed under the terms of the GNU GPL v2.
