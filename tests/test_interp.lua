local lu = require('luaunit')
local Interpreter = require('luaturtle.interp')

local TestInterp = {}

local function doScriptTest( script )
   local i = Interpreter:new()
   for _,line in ipairs(script) do
      local given = line[1]
      local expected = line[2]
      local status, rv = i:repl( given )
      lu.assertEquals( status, true, tostring(rv) )
      lu.assertEquals( tostring(rv), expected, given )
   end
end

function TestInterp.testRepl1()
   doScriptTest({
         { '1+2', '3' }, --[[
         { 'var x = 4*10 + 2;', 'undefined' },
         { 'x', '42' },
         { 'console.log("seems to work");', 'undefined' },
         { "var fib = function(n) { return (n<2) ? 1 : fib(n-1) + fib(n-2); };", "undefined" },
         { "fib(10)", "89" },
   })
end

function TestInterp.testParseInt()
   doScriptTest({
         -- sanity check numeric types
         { "NaN", "NaN" },
         { "Infinity", "Infinity" },
         { "-Infinity", "-Infinity" },
         -- test parseInt
         { "parseInt('10', 16)", "16" },
         { "parseInt('10', '16')", "16" },
         { "parseInt('10', -10)", "NaN" },
         { "parseInt('10', -1)", "NaN" },
         { "parseInt('10', 'a')", "10" },
         { "parseInt('10', 'ab')", "10" },
         { "parseInt('10', NaN)", "10" },
         { "parseInt('10', 'NaN')", "10" },
         { "parseInt('10', Infinity)", "10" },
         { "parseInt('10', 'Infinity')", "10" },
         { "parseInt('10', -Infinity)", "10" },
         { "parseInt('10', '-Infinity')", "10" },
         { "parseInt('11')", "11" },
         { "parseInt('11z')", "11"},
         { "parseInt(' 11z')", "11"},
         { "parseInt('10', '16.5')", "16" },
         { "parseInt('10', 16.5)", "16" },
   } )
end

function TestInterp.testCmp()
   doScriptTest( {
         { "'2' > '10'", "true" },
         { "2 > 10", "false" },
         { "2 > '10'", "false" },
         { "'2' > 10", "false" },
         { "'2' >= '10'", "true" },
         { "2 >= 10", "false" },
         { "2 >= '10'", "false" },
         { "'2' >= 10", "false" },
         { "'z' > 10", "false" },
         { "'z' < 10", "false" },
   } )
end

function TestInterp.testMul()
      doScriptTest( {
            { "' 10z' * 1", "NaN" },
            { "' 10 ' * 1", "10" },
      } )
end

function TestInterp.testNumber_toString()
   doScriptTest( {
         { "Infinity.toString()", "Infinity" },
         { "Infinity.toString(16)", "Infinity" },
         { "NaN", "NaN" },
         { "NaN.toString(16)", "NaN" },
   } )
end

function TestInterp.testString_charAt()
   doScriptTest( {
         { "'abc'.charAt()", "a" },
         { "'abc'.charAt(-1)", "" },
         { "'abc'.charAt(1)", "b" },
         { "'abc'.charAt(4)", "" },
         { "'abc'.charAt(NaN)", "a" },
         { "'abc'.charAt('a')", "a" },
         { "'abc'.charAt(1.2)", "b" },
         { "'abc'.charAt(2.9)", "c" },
   } )
end

function TestInterp.testMath_floor()
   doScriptTest( {
         { "Math.floor(-1.1)", "-2" },
         { "Math.floor(-1)", "-1" },
         { "Math.floor(0)", "0" },
         { "Math.floor(3)", "3" },
         { "Math.floor(3.2)", "3" },
         { "Math.floor({})", "NaN" },
         { "Math.floor([])", "0" },
         { "Math.floor([1])", "1" },
         { "Math.floor([1,2])", "NaN" },
         { "Math.floor('abc')", "NaN" },
         { "Math.floor(' 10 ')", "10" },
         { "Math.floor()", "NaN" },
   } )
end

function TestInterp.testBoolean()
   doScriptTest( {
         { "Boolean(true)", "true" },
         { "Boolean(false)", "false" },
         { "Boolean(0)", "false" },
         { "Boolean(NaN)", "false" },
         { "Boolean('abc')", "true" },
         { "Boolean('')", "false" },
         { "Boolean(123)", "true" },
   } )
end

function TestInterp.testToNumber()
   doScriptTest( {
         { "11 * 1", "11" },
         { "' 11\\n' * 1", "11" },
         { "' -11\\n' * 1", "-11" },
         { "true * 1", "1" },
         { "false * 1", "0" },
         { "null * 1", "0" },
         { "undefined * 1", "NaN" },
         { "'xxx' * 1", "NaN" },
         { "'Infinity' * 1", "Infinity" },
         { "'-Infinity' * 1", "-Infinity" },
         { "'inf' * 1", "NaN" },
         { "'-inf' * 1", "NaN" },
         { "'NaN' * 1", "NaN" },
         { "1e1 * 1", "10" },
         { "'1e1' * 1", "10" },
         { "'0x10' * 1", "16" },
         { "'' * 1", "0" },
   } )
end

function TestInterp.testObjEq()
   doScriptTest( {
         { "var x = {};", "undefined" },
         { "var y = { f: x };", "undefined" },
         { "var z = { f: x };", "undefined" },
         { "y===z", "false" },
         { "x===x", "true" },
         { "y.f === z.f", "true" },
         { "z.f = {};", "undefined" },
         { "y.f === z.f", "false" },
   } )
end

function TestInterp.testString_valueOf()
   doScriptTest( {
         { "var x = 'abc';", "undefined" },
         { "x.valueOf()", "abc" },
         { "x.toString()", "abc" },
         { "x === x.valueOf()", "true" },
         { "x === x.toString()", "true" },
         { "x === x", "true" },
         -- XXX: now with a wrapped string object
   } )
end

function TestInterp.testArray_join()
   doScriptTest( {
         { "var a = [1,2,3];", "undefined" },
         { "a.toString()", "1,2,3" },
         { "a.join(':')", "1:2:3" },
         { "a.join(4)", "14243" },
         ]]
   } )
end

return TestInterp
