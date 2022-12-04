local lu = require('luaunit')
local jsval = require('luaturtle.jsval')

local TestJsVal = {}

function TestJsVal.testJsNumberAdd()
   local a = jsval.newNumber(5)
   local b = jsval.newNumber(6)
   lu.assertEquals(jsval.Type(a), 'Number')
   lu.assertEquals(jsval.Type(b), 'Number')

   local c = a + b
   lu.assertEquals(jsval.Type(c), 'Number')
   lu.assertEquals(tostring(c), '11')

   local d = a + jsval.True
   lu.assertEquals(jsval.Type(d), 'Number')
   lu.assertEquals(tostring(d), '6')

   local e = jsval.True + a
   lu.assertEquals(jsval.Type(e), 'Number')
   lu.assertEquals(tostring(e), '6')
end

function TestJsVal.testJsNumberSub()
   local a = jsval.newNumber(5)
   local b = jsval.newNumber(6)
   lu.assertEquals(jsval.Type(a), 'Number')
   lu.assertEquals(jsval.Type(b), 'Number')

   local c = b - a
   lu.assertEquals(jsval.Type(c), 'Number')
   lu.assertEquals(tostring(c), '1')

   local d = a - jsval.True
   lu.assertEquals(jsval.Type(d), 'Number')
   lu.assertEquals(tostring(d), '4')

   local e = jsval.False - a
   lu.assertEquals(jsval.Type(e), 'Number')
   lu.assertEquals(tostring(e), '-5')

   local f = jsval.newString('10')
   local g = f - b
   lu.assertEquals(jsval.Type(g), 'Number')
   lu.assertEquals(tostring(g), '4')

   local h = a - f
   lu.assertEquals(jsval.Type(h), 'Number')
   lu.assertEquals(tostring(h), '-5')
end

function TestJsVal.testJsString()
   local a = jsval.newString('abc')
   local b = jsval.newString('defg')
   lu.assertEquals(jsval.Type(a), 'String')
   lu.assertEquals(jsval.Type(b), 'String')

   local c = a + b + a
   lu.assertEquals(jsval.Type(c), 'String')
   lu.assertEquals(tostring(c), 'abcdefgabc')
   lu.assertEquals(jsval.strlen(c), 10) -- #c in Lua >= 5.2

   -- now test again w/o utf8 conversion first
   local d = b + a + b
   lu.assertEquals(jsval.strlen(d), 11) -- #d in Lua >= 5.2

   -- number conversion to string, too
   local e = jsval.newNumber(5)
   local f = a + e
   lu.assertEquals(jsval.Type(f), 'String')
   lu.assertEquals(tostring(f), 'abc5')

   local g = e + a
   lu.assertEquals(jsval.Type(g), 'String')
   lu.assertEquals(tostring(g), '5abc')
end

function TestJsVal.testJsObject()
   local o = jsval.newObject(nil, jsval.Null)
   local o2 = jsval.newObject(nil, o)
   -- test the __index / __newindex overrides and property inheritance
   o.b = 5
   lu.assertEquals(o.b, 5);
   lu.assertEquals(o2.b, 5);
   o2.b = 6
   lu.assertEquals(o.b, 5);
   lu.assertEquals(o2.b, 6);

   lu.assertEquals(o.a, nil)
   lu.assertEquals(o2.a, nil)
end

return TestJsVal
