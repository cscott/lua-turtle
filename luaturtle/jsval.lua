-- JavaScript value types
-- In the future we could gain efficiency by unwrapping some of these
-- primitive types, but for now let's wrap everything.
local utf8 = require('utf8')
local table = require('table')
local string = require('string')

local jsval = {}

-- private slot keys
local function mkPrivateSlot(name)
   return setmetatable({}, { __tostring = function() return name end })
end
local DEFAULTENV = mkPrivateSlot('@DEFAULTENV@')
local PARENTFRAME = mkPrivateSlot('@PARENTFRAME@')
local VALUE = mkPrivateSlot('@VALUE@')
local ISAPPLY = mkPrivateSlot('@ISAPPLY@')
-- private slots in the JS standard
local PROTOTYPE = mkPrivateSlot('[[Prototype]]')
local EXTENSIBLE = mkPrivateSlot('[[Extensible]]')
local BOOLEANDATA = mkPrivateSlot('[[BooleanData]]')
local NUMBERDATA = mkPrivateSlot('[[NumberData]]')
local SYMBOLDATA = mkPrivateSlot('[[SymbolData]]')
local STRINGDATA = mkPrivateSlot('[[StringData]]')

-- helper to call 'hidden' functions on metatable
local function mt(env, v, name, ...)
   if true then -- debugging code, disable later for speed in this hot path
      local vm = getmetatable(v)
      if vm == nil or vm[name] == nil then
         local ty = vm and vm.Type
         if ty ~= nil then ty = ty() else ty = '<unknown>' end
         if v == nil then ty = 'nil' end
         error('NYI ' .. name .. ' in ' .. ty)
      end
   end
   return getmetatable(v)[name](env, v, ...)
end

local function ThrowTypeError(env, msg)
   if env ~= nil then
      local obj = env:newTypeError(msg)
      error(obj)
   end
   error('TypeError: ' .. msg)
end

local function nyi(msg)
   return function() error('not yet implemented: ' + msg) end
end

-- PropertyDescriptor describes a slot in the JavaScript object
local PropertyDescriptor = {}
PropertyDescriptor.__index = PropertyDescriptor
function PropertyDescriptor:new(desc)
   -- note! the `value`, `get` and `set` fields can be present but Undefined
   desc = desc or {}
   setmetatable(desc, self)
   return desc
end
function PropertyDescriptor:newSimple(value)
   return self:new{
      value = value,
      writable = true,
      enumerable = true,
      configurable = true
   }
end
function PropertyDescriptor:newData(desc)
   return self:new{
      value = desc.value or Undefined,
      writable = desc.writable or false,
      enumerable = desc.enumerable or false,
      configurable = desc.configurable or false
   }
end
function PropertyDescriptor:newAccessor(desc)
   return self:new{
      get = desc.get or Undefined,
      set = desc.set or Undefined,
      enumerable = desc.enumerable or false,
      configurable = desc.configurable or false
   }
end
function PropertyDescriptor:clone()
   local npd = PropertyDescriptor:new{}
   npd:setFrom(self)
   return npd
end
function PropertyDescriptor:setFrom(P)
   if P.value ~= nil then self.value = P.value end
   if P.get ~= nil then self.get = P.get end
   if P.set ~= nil then self.set = P.set end
   if P.writable ~= nil then self.writable = P.writable end
   if P.enumerable ~= nil then self.enumerable = P.enumerable end
   if P.configurable ~= nil then self.configurable = P.configurable end
   return self
end
function PropertyDescriptor:IsEmpty()
   return self.value == nil and self.get == nil and self.set == nil and
      self.writable == nil and self.enumerable == nil and
      self.configurable == nil
end
function PropertyDescriptor:IsSimple(noDefaults)
   return
      (self.writable == true or (noDefaults and self.writable == nil)) and
      (self.configurable == true or (noDefaults and self.configurable == nil)) and
      (self.enumerable == true or (noDefaults and self.enumerable == nil))
end
function PropertyDescriptor:IsAccessorDescriptor()
   if self == nil then return false end
   if self.get == nil and self.set == nil then return false end
   return true
end
function PropertyDescriptor:IsDataDescriptor()
   if self == nil then return false end
   if self.value == nil and self.writable == nil then return false end
   return true
end
function PropertyDescriptor:IsGenericDescriptor()
   if self == nil then return false end
   if (not self:IsAccessorDescriptor()) and (not self:IsDataDescriptor()) then
      return true
   end
   return false
end

-- EcmaScript language types
local function extendMT(oldmt)
   local newmt = setmetatable({}, { __index = oldmt })
   local metamethods = {
      '__tostring', '__add', '__sub', '__index', '__newindex'
   }
   for i,name in ipairs(metamethods) do
      local func = rawget(oldmt, name)
      if func ~= nil then
         rawset(newmt, name, func)
      end
   end
   return newmt
end
local JsValMT = {
   isJsVal = true,
   Type = nyi('Type'),
   ToPrimitive = nyi('ToPrimitive'),
   ToObject = nyi('ToObject'),
   GetMethod = nyi('GetMethod'),
   Call = nyi('Call'),
   SameValue = nyi('SameValue'),
}
local UndefinedMT = extendMT(JsValMT)
local NullMT = extendMT(JsValMT)
local BooleanMT = extendMT(JsValMT)
local StringMT = extendMT(JsValMT)
local SymbolMT = extendMT(JsValMT)
local NumberMT = extendMT(JsValMT)
local BigIntMT = extendMT(JsValMT)
local ObjectMT = extendMT(JsValMT)

local allTypes = {
   UndefinedMT, NullMT, BooleanMT, StringMT,
   SymbolMT, NumberMT, BigIntMT, ObjectMT
}
local function copyToAll(name)
   for i, ty in ipairs(allTypes) do
      ty[name] = JsValMT[name]
   end
end

-- Constructors
local Undefined = setmetatable({}, UndefinedMT)
local Null = setmetatable({}, NullMT)
function NumberMT:from(value)
   return setmetatable({ value = value }, self)
end
local True = setmetatable(
   { value = true, number = NumberMT:from(1) }, BooleanMT)
local False = setmetatable(
   { value = false, number = NumberMT:from(0) }, BooleanMT)
function ObjectMT:create(env, proto)
   -- OrdinaryObjectCreate, more or less
   assert(proto ~= nil)
   return setmetatable(
      { [DEFAULTENV] = env, [PROTOTYPE] = proto, [EXTENSIBLE] = true },
      ObjectMT)
end

-- String constructors
function StringMT:cons(a, b)
   if a ~= nil and type(a) ~= 'string' then
      if a.prefix == nil then
         a = a.suffix
      elseif a.suffix == nil then
         a = a.prefix
      end
   end
   if b ~= nil and type(b) ~= 'string' then
      if b.prefix == nil then
         b = b.suffix
      elseif b.suffix == nil then
         b = b.prefix
      end
   end
   return setmetatable({ prefix=a, suffix=b }, self)
end
function StringMT:fromUTF8(s)
   local result = {}
   local push16 = function(c)
      table.insert(result, string.char(c >> 8, c & 0xFF))
   end
   for p,c in utf8.codes(s) do
      if c <= 0xD7FF or (c >= 0xE000 and c <= 0xFFFF) then
         push16(c)
      else
         assert(c >= 0x10000, "unpaired surrogate")
         c = c - 0x10000
         push16(0xD800 + (c >> 10))
         push16(0xDC00 + (c & 0x3FF))
      end
   end
   local obj = StringMT:cons(nil, table.concat(result))
   obj.utf8 = s -- optimization!
   return obj
end
function StringMT:flatten(s)
   if s.prefix == nil then return s end
   local result = {}
   local stack = { '' }
   local ss = s
   while #stack > 0 do
      if type(ss) == 'string' then
         table.insert(result, ss)
         ss = table.remove(stack)
      elseif ss.prefix == nil then
         ss = ss.suffix
      else
         table.insert(stack, ss.suffix)
         ss = ss.prefix
      end
   end
   s.prefix = nil
   s.suffix = table.concat(result)
   return s
end

-- String Intern table
local stringInternTable = {}
function StringMT:intern(s)
   -- fast case
   local r = stringInternTable[s]
   if r ~= nil then return r end
   -- slower case
   if type(s) == 'string' then
      r = StringMT:fromUTF8(s)
      stringInternTable[s] = r
      return r
   end
   -- more unusual case, called w/ a JS object
   assert(mt(nil, s, 'Type') == 'String')
   local key = tostring(s)
   stringInternTable[key] = s
   return s
end

-- Convert values to/from lua
local function isJsVal(v)
   if type(v) == 'table' then
      local mt = getmetatable(v)
      if mt ~= nil and mt.isJsVal == true then return true end
   end
   return false
end

local function fromLua(env, v)
   if isJsVal(v) then return v end -- fast path: already converted!
   local ty = type(v)
   if ty == 'string' then
      return StringMT:fromUTF8(v)
   elseif ty == 'number' then
      return NumberMT:from(v)
   end
   ThrowTypeError(env, "Can't convert Lua type " .. ty .. " to JS")
end
local function toLua(env, jsval)
   assert(isJsVal(jsval), jsval)
   return mt(env, jsval, 'toLua')
end

-- lua pretty-printing (but tostring isn't a virtual dispatch by default)
function JsValMT:__tostring() return mt(nil, self, 'Type') end
copyToAll('__toString')
function UndefinedMT:__tostring() return 'undefined' end
function NullMT:__tostring() return 'null' end
function BooleanMT:__tostring() return tostring(self.value) end
-- StringMT.__tostring is actually defined lower down
function NumberMT:__tostring() return tostring(self.value) end
function PropertyDescriptor:__tostring()
   local s = ''
   for k,v in pairs(self) do
      s = s .. k .. '=' .. tostring(v) .. ','
   end
   return 'PropertyDescriptor{' .. s .. '}'
end

function JsValMT:toLua(env, val)
   ThrowTypeError(env, "Can't convert "..tostring(val).." to Lua")
end
function UndefinedMT.toLua() return nil end
function NullMT.toLua() return nil end
function BooleanMT.toLua(env, b) return b.value end
function NumberMT.toLua(env, n) return n.value end
function StringMT.toLua(env, s) return tostring(s) end

-- Type (returns lua string, not js string)
function UndefinedMT.Type() return 'Undefined' end
function NullMT.Type() return 'Null' end
function BooleanMT.Type() return 'Boolean' end
function StringMT.Type() return 'String' end
function SymbolMT.Type() return 'Symbol' end
function NumberMT.Type() return 'Number' end
function BigIntMT.Type() return 'BigInt' end
function ObjectMT.Type() return 'Object' end
-- internal object types
function PropertyDescriptor.Type() return 'PropertyDescriptor' end

-- typeof
function UndefinedMT.typeof() return StringMT:intern('undefined') end
function NullMT.typeof() return StringMT:intern('object') end
function BooleanMT.typeof() return StringMT:intern('boolean') end
function NumberMT.typeof() return StringMT:intern('number') end
function StringMT.typeof() return StringMT:intern('string') end
function SymbolMT.typeof() return StringMT:intern('symbol') end
function BigIntMT.typeof() return StringMT:intern('bigint') end
function ObjectMT.typeof(env, obj)
   if getmetatable(obj)['[[Call]]'] == nil then
      return StringMT:intern('object')
   else
      return StringMT:intern('function')
   end
end

-- IsPropertyDescriptor (returns lua boolean, not js boolean)
function IsPropertyDescriptor(v) -- faster
   return getmetatable(v) == PropertyDescriptor
end

-- IsObject (returns lua boolean, not js boolean)
function JsValMT.IsObject() return false end
function ObjectMT.IsObject() return true end

-- ToObject
function UndefinedMT.ToObject(env, undef)
   return ThrowTypeError(env, 'ToObject on undefined')
end
function NullMT.ToObject(env, undef)
   return ThrowTypeError(env, 'ToObject on null')
end
function BooleanMT.ToObject(env, b)
   local O = ObjectMT:create(env, env.realm.BooleanPrototype)
   rawset(O, BOOLEANDATA, b)
   return O
end
function StringMT.ToObject(env, s)
   -- StringCreate 9.4.3.4
   local O = ObjectMT:create(env, env.realm.StringPrototype)
   rawset(O, STRINGDATA, s)
   mt(env, O, 'DefinePropertyOrThrow', StringMT:intern('length'),
      PropertyDescriptor:newData{ value = Number:from(#s) } )
   setmetatable(O, getmetatable(env.realm.StringPrototype))
   return O
end
function SymbolMT.ToObject(env, s)
   local O = ObjectMT:create(env, env.realm.SymbolPrototype)
   rawset(O, SYMBOLDATA, s)
   return O
end
function NumberMT.ToObject(env, num)
   local O = ObjectMT:create(env, env.realm.NumberPrototype)
   rawset(O, NUMBERDATA, num)
   return O
end
function ObjectMT.ToObject(env, obj)
   return obj
end

-- ToPrimitive / OrdinaryToPrimitive
function JsValMT.ToPrimitive(env, val, hint)
   return val
end
function ObjectMT.ToPrimitive(env, input, hint)
   hint = hint or 'default'
   if env == nil then env = rawget(input, DEFAULTENV) end -- support for lua interop
   local exoticToPrim = mt(env, input, 'GetMethod', env.symbols.toPrimitive)
   if not rawequal(exoticToPrim, Undefined) then
      local result = mt(env, exoticToPrim, 'Call', StringMT:intern(hint))
      if mt(env, result, 'IsObject') then
         ThrowTypeError(env, 'exotic ToPrimitive not primitive')
      end
      return result
   end
   if hint == 'default' then
      hint = 'number'
   end
   return mt(env, input, 'OrdinaryToPrimitive', hint)
end

function ObjectMT.OrdinaryToPrimitive(env, O, hint)
   local methodNames
   if hint == 'string' then
      methodNames = { 'toString', 'valueOf' }
   else
      methodNames = { 'valueOf', 'toString' }
   end
   for i=1,2 do
      local method = mt(env, O, 'Get', StringMT:intern(methodNames[i]))
      if mt(env, method, 'IsCallable') then
         local result = mt(env, method, 'Call', O)
         if not mt(env, result, 'IsObject') then
            return result
         end
      end
   end
   ThrowTypeError(env, 'Failed to convert to primitive')
end

-- ToBoolean -- returns JS boolean, not lua boolean
function UndefinedMT.ToBoolean() return False end
function NullMT.ToBoolean() return False end
function BooleanMT.ToBoolean(env, b) return b end
function NumberMT.ToBoolean(env, n)
   n = n.value
   if n == 0 or (n ~= n) then return False end
   return True
end
function StringMT.ToBoolean(env, s)
   if StringMT.IsZeroLength(s) then return False end
   return True
end
function SymbolMT.ToBoolean() return True end
function ObjectMT.ToBoolean() return True end

-- ToNumeric
function JsValMT.ToNumeric(env, value)
   local primValue = mt(env, value, 'ToPrimitive', 'number')
   if mt(env, primValue, 'Type') == 'BigInt' then
      return primValue
   end
   return mt(env, primValue, 'ToNumber')
end

-- ToNumber
function UndefinedMT.ToNumber() return NumberMT:from(0/0) end
function NullMT.ToNumber() return NumberMT:from(0) end
function BooleanMT.ToNumber(env, b) return b.number end
function NumberMT.ToNumber(env, n) return n end
function StringMT.ToNumber(env, s)
   -- XXX this isn't fully spec-compliant
   local n = tonumber(tostring(s))
   if n == nil then n = (0/0) end
   return NumberMT:from(n)
end
function SymbolMT.ToNumber(env)
   ThrowTypeError(env, 'Symbol#toNumber')
end
function BigIntMT.ToNumber(env)
   ThrowTypeError(env, 'BigInt#toNumber')
end
function ObjectMT.ToNumber(env, argument)
   if env == nil then env = rawget(argument, DEFAULTENV) end -- support for lua interop
   local primValue = mt(env, argument, 'ToPrimitive', 'number')
   return mt(env, primValue, 'ToNumber')
end

function JsValMT.ToInteger(env, argument)
   local number = mt(env, argument, 'ToNumber')
   assert(mt(env, number, 'Type') == 'Number')
   return NumberMT.ToInteger(env, number)
end
function NumberMT.ToInteger(env, argument)
   local number = argument.value
   if number ~= number then return NumberMT:from(0) end -- NaN
   if number == 0 then return argument end -- +0.0 and -0.0
   if number == (1/0) or number == (-1/0) then return argument end -- Infinities
   local minus = (number < 0)
   number = math.floor(math.abs(number))
   if minus then number = -number end
   return NumberMT:from(number)
end

function JsValMT.ToUint32(env, argument)
   local number = mt(env, argument, 'ToNumber')
   assert(mt(env, number, 'Type') == 'Number')
   return NumberMT.ToUint32(env, number)
end
function NumberMT.ToUint32(env, argument)
   local number = argument.value
   if (number ~= number or -- NaN
       number == 0 or -- +0.0 and -0.0
       number == (1/0) or number == (-1/0)) then -- Infinities
      return NumberMT:from(0)
   end
   local minus = (number < 0)
   number = math.floor(math.abs(number))
   if minus then number = -number end
   return NumberMT:from(number & 0xFFFFFFFF)
end

-- ToString
local toStringVals = {
   [Undefined] = StringMT:intern('undefined'),
   [Null] = StringMT:intern('null'),
   [True] = StringMT:intern('true'),
   [False] = StringMT:intern('false'),
}
function JsValMT.ToString(env, val) return toStringVals[val] end
function NumberMT.ToString(env, val)
   -- XXX not entirely spec compliant
   local s = StringMT:fromUTF8(tostring(val.value))
   -- fast-ish path for converting back to number for array index, etc
   rawset(s, 'number', val)
   return s
end
function StringMT.ToString(env, val) return val end
function SymbolMT.ToString(env, val)
   ThrowTypeError(env, "can't convert Symbol to string")
end
BigIntMT.ToString = nyi('BigInt ToString')
function ObjectMT.ToString(env, val)
   local primValue = mt(env, val, 'ToPrimitive', 'string')
   return mt(env, primValue, 'ToString')
end

-- ToObject
function JsValMT.ToString(env, val)
   ThrowTypeError(env, "can't convert to object")
end
-- XXX Boolean/Number/String/Symbol/BigInt; see 7.1.18
function ObjectMT.ToString(env, val) return val end

-- ToPropertyKey
function JsValMT.ToPropertyKey(env, val)
   local key = mt(env, val, 'ToPrimitive', 'string')
   if mt(env, key, 'Type') == 'Symbol' then return key end
   return mt(env, key, 'ToString')
end
function NumberMT.ToPropertyKey(env, val)
   return NumberMT.ToString(env, val) -- sort of fast path (kinda slow)
end
-- Fast path for string and symbol
function SymbolMT.ToPropertyKey(env, val) return val end
function StringMT.ToPropertyKey(env, val) return val end

-- ToLength
function JsValMT.ToLength(env, val)
   local len = mt(env, val, 'ToInteger') -- assume unboxed
   if len <= 0 then return 0 end
   -- XXX clamp len to 2^53 - 1
   return len
end

-- CanonicalNumericIndexString
function StringMT.CanonicalNumericIndexString(env, val)
   if val.number ~= nil then return val.number end -- fast path!
   if StringMT.equals(val, StringMT:intern("-0")) then
      return NumberMT:from(-1/(1/0)) -- -0.0
   end
   local n = mt(env, val, 'ToNumber')
   if StringMT.equals(val, mt(env, n, 'ToString')) then
      return n
   end
   return Undefined
end

-- ToIndex

-- thisBooleanValue (19.3.3)
function JsValMT.thisBooleanValue(env, val)
   ThrowTypeError(env, 'Not a boolean value!')
end
function BooleanMT.thisBooleanValue(env, value)
   return value
end
function ObjectMT.thisBooleanValue(env, obj)
   local b = rawget(obj, BOOLEANDATA)
   if b == nil then
      ThrowTypeError(env, 'Not a boolean value!')
   end
   assert(mt(env, b, 'Type') == 'Boolean')
   return b
end

-- thisNumberValue (20.1.3)
function JsValMT.thisNumberValue(env, val)
   ThrowTypeError(env, 'Not a number value!')
end
function NumberMT.thisNumberValue(env, value)
   return value
end
function ObjectMT.thisNumberValue(env, obj)
   local n = rawget(obj, NUMBERDATA)
   if n == nil then
      ThrowTypeError(env, 'Not a number value!')
   end
   assert(mt(env, n, 'Type') == 'Number')
   return n
end

-- IsCallable (returns lua boolean, not Js boolean)
function JsValMT.IsCallable(env) return false end
function ObjectMT.IsCallable(env, argument)
   return (getmetatable(argument)['[[Call]]'] ~= nil)
end

-- IsConstructor (returns lua boolean, not Js boolean)
function JsValMT.IsConstructor(env) return false end
function ObjectMT.IsConstructor(env, argument)
   return (getmetatable(argument)['[[Construct]]'] ~= nil)
end

-- IsExtensible (returns lua boolean, not js boolean)
function JsValMT.IsExtensible(env) assert(false, 'IsExtensible on prim') end
function ObjectMT.IsExtensible(env, obj)
   return mt(env, obj, '[[IsExtensible]]')
end

-- DefinePropertyOrThrow (7.3.8)
function ObjectMT.DefinePropertyOrThrow(env, O, P, desc)
   local success = mt(env, O, '[[DefineOwnProperty]]', P, desc)
   if not success then ThrowTypeError(env, "Can't define property") end
   return success
end

-- HasProperty (7.3.11)
function ObjectMT.HasProperty(env, O, P)
   return mt(env, O, '[[HasProperty]]', P)
end

-- HasOwnProperty (7.3.12)
function ObjectMT.HasOwnProperty(env, O, P)
   local desc = mt(env, O, '[[GetOwnProperty]]', P)
   if desc == nil then return False end
   return True
end

-- Get/GetV
function JsValMT.GetV(env, V, P)
   local O = mt(env, V, 'ToObject')
   return mt(env, O, '[[Get]]', P, V)
end
function ObjectMT.Get(env, O, P)
   return mt(env, O, '[[Get]]', P, O)
end
ObjectMT.GetV = ObjectMT.Get -- optimization

-- Set
function ObjectMT.Set(env, O, P, V, Throw)
   local success = mt(env, O, '[[Set]]', P, V, O)
   if (not success) and Throw then
      ThrowTypeError(env, 'Failed to set')
   end
   return success
end

-- [[HasProperty]] (9.1.7)
-- OrdinaryHasProperty (9.1.7.1)
function OrdinaryHasProperty(env, O, P)
   local hasOwn = mt(env, O, '[[GetOwnProperty]]', P)
   if hasOwn ~= nil then return true end
   local parent = mt(env, O, '[[GetPrototypeOf]]')
   if not rawequal(parent, Null) then
      return mt(env, parent, '[[HasProperty]]', P)
   end
   return false
end
ObjectMT.OrdinaryHasProperty = OrdinaryHasProperty
ObjectMT['[[HasProperty]]'] = OrdinaryHasProperty

function ObjectMT.OrdinaryGet(env, O, P, Receiver)
   -- fast path! inlined from OrdinaryGetOwnProperty impl
   local desc
   local GetOwnProperty = getmetatable(O)['[[GetOwnProperty]]']
   local fastKey = rawget(P, 'key')
   if GetOwnProperty == OrdinaryGetOwnProperty and fastKey ~= nil then
      local fastVal = rawget(O, fastKey)
      if fastVal == nil then
         desc = nil -- this is fast path for method lookup through prototype
      elseif getmetatable(fastVal) == PropertyDescriptor then
         desc = fastVal -- moderately fast path for method lookup
      else
         return fastVal -- super fast path for a simple value
      end
   else
      desc = GetOwnProperty(env, O, P)
   end
   if desc == nil then
      local parent = mt(env, O, '[[GetPrototypeOf]]')
      if rawequal(parent, Null) then return Undefined end
      return mt(env, parent, '[[Get]]', P, Receiver)
   end
   if desc:IsDataDescriptor() then
      if desc.value == nil then return Undefined end
      return desc.value
   end
   local getter = desc.get
   if getter == nil or rawequal(getter, Undefined) then return Undefined end
   return mt(env, getter, 'Call', Receiver)
end
ObjectMT['[[Get]]'] = ObjectMT.OrdinaryGet

function ObjectMT.OrdinarySet(env, O, P, V, Receiver)
   -- fast path! inlined from OrdinaryGetOwnProperty impl
   local GetOwnProperty = getmetatable(O)['[[GetOwnProperty]]']
   if rawequal(O, Receiver) and GetOwnProperty == OrdinaryGetOwnProperty then
      local fastKey = rawget(P, 'key')
      if fastKey ~= nil then
         local fastVal = rawget(O, fastKey)
         if fastVal ~= nil and getmetatable(fastVal) ~= PropertyDescriptor then
            -- fast path for a set of a simple value
            rawset(O, fastKey, V)
            return true
         end
      end
   end
   local ownDesc = GetOwnProperty(env, O, P)
   return mt(env, O, 'OrdinarySetWithOwnDescriptor', P, V, Receiver, ownDesc)
end
ObjectMT['[[Set]]'] = ObjectMT.OrdinarySet

function ObjectMT.OrdinarySetWithOwnDescriptor(env, O, P, V, Receiver, ownDesc)
   if ownDesc == nil then
      local parent = mt(env, O, '[[GetPrototypeOf]]')
      if not rawequal(parent, Null) then
         return mt(env, parent, '[[Set]]', P, V, Receiver)
      else
         ownDesc = PropertyDescriptor:newSimple(Undefined)
      end
   end
   if ownDesc:IsDataDescriptor() then
      if not ownDesc.writable then return false end
      if not mt(env, Receiver, 'IsObject') then return false end
      local existingDescriptor = mt(env, Receiver, '[[GetOwnProperty]]', P)
      if existingDescriptor ~= nil then
         if existingDescriptor:IsAccessorDescriptor() then return false end
         if existingDescriptor.writable == false then return false end
         local valueDesc = PropertyDescriptor:new{ value = V }
         return mt(env, Receiver, '[[DefineOwnProperty]]', P, valueDesc)
      else
         -- inlined CreateDataProperty(Receiver, P, V)
         local newDesc = PropertyDescriptor:newSimple(V)
         return mt(env, Receiver, '[[DefineOwnProperty]]', P, newDesc)
      end
   end
   -- ownDesc is an accessor descriptor
   local setter = ownDesc.set
   if setter == nil or rawequal(setter, Undefined) then return false end
   mt(env, setter, 'Call', Receiver, V)
   return true
end

-- [[Delete]] / OrdinaryDelete (9.1.10)
function OrdinaryDelete(env, O, P)
   local desc = mt(env, O, '[[GetOwnProperty]]', P)
   if desc == nil then return true end
   if desc.configurable == true then
      local field = mt(env, P, 'toKey')
      rawset(O, field, nil)
      return true
   end
   return false
end
ObjectMT.OrdinaryDelete = OrdinaryDelete
ObjectMT['[[Delete]]'] = OrdinaryDelete

-- [[GetPrototypeOf]] / [[SetPrototypeOf]]
function OrdinaryGetPrototypeOf(env, obj)
   return rawget(obj, PROTOTYPE)
end
ObjectMT.OrdinaryGetPrototypeOf = OrdinaryGetPrototypeOf
ObjectMT['[[GetPrototypeOf]]'] = OrdinaryGetPrototypeOf

function ObjectMT.OrdinarySetPrototypeOf(env, O, V)
   assert(rawequal(V, Null) or mt(env, V, 'IsObject'), 'bad prototype')
   local current = rawget(O, PROTOTYPE)
   if mt(env, V, 'SameValue', current) then return true end
   if rawget(O, EXTENSIBLE) == false then return false end
   local p = V
   local done = false
   while done == false do
      if rawequal(p, Null) then
         done = true
      elseif mt(env, p, 'SameValue', O) then
         return false -- prototype cycle!  bail!
      else
         if getmetatable(p)['[[GetPrototypeOf]]'] ~= OrdinaryGetPrototypeOf then
            done = true
         else
            p = rawget(p, PROTOTYPE) or Null
         end
      end
   end
   rawset(O, PROTOTYPE, V)
   return true
end
ObjectMT['[[SetPrototypeOf]]'] = OrdinarySetPrototypeOf

function ObjectMT.SetImmutablePrototype(env, O, V)
   local current = mt(env, O, '[[GetPrototypeOf]]')
   if mt(env, V, 'SameValue', current) then
      return true
   else
      return false
   end
end

function ObjectMT.OrdinaryIsExtensible(env, obj)
   return rawget(obj, EXTENSIBLE) ~= false
end
ObjectMT['[[IsExtensible]]'] = ObjectMT.OrdinaryIsExtensible

function ObjectMT.OrdinaryPreventExtensions(env, obj)
   rawset(obj, EXTENSIBLE, false)
   return true
end
ObjectMT['[[PreventExtensions]]'] = ObjectMT.OrdinaryPreventExtensions

-- returns nil or a PropertyDescriptor
-- Note that a fast path from this is inlined into [[Get]] and [[Set]]
function OrdinaryGetOwnProperty(env, O, P)
   -- P is a String or a Symbol
   local field = mt(env, P, 'toKey')
   local valOrDesc = rawget(O, field)
   if valOrDesc == nil then return nil end
   if IsPropertyDescriptor(valOrDesc) then
      return valOrDesc
   else
      return PropertyDescriptor:newSimple(valOrDesc)
   end
end
ObjectMT.OrdinaryGetOwnProperty = OrdinaryGetOwnProperty
ObjectMT['[[GetOwnProperty]]'] = OrdinaryGetOwnProperty

function ObjectMT.StringGetOwnProperty(env, S, P) -- 9.4.3.5
   assert(rawget(S, STRINGDATA) ~= nil)
   if mt(env, P, 'Type') ~= 'String' then return nil end
   local index = mt(env, P, 'CanonicalNumericIndexString')
   if rawequal(index, Undefined) then return nil end
   assert(mt(env, index, 'Type') == 'Number')
   if not mt(env, index, 'IsInteger') then return nil end
   -- test for -0.0
   if index.value == 0 and (1/index.value) == (-1/0) then return nil end
   if index.value < 0 then return nil end
   local str = rawget(S, STRINGDATA)
   console.assert(str~=nil and mt(env, str, 'Type') == 'String')
   local len = #str
   if len <= index then return nil end
   local start = (index << 1) + 1 -- 1-based indexing!
   local resultStr = string.sub(StringMT:flatten(str).suffix, start, start+1)
   return PropertyDescriptor:newData{
      value = StringMT:cons(nil, resultStr),
      enumerable = true,
   }
end

function ObjectMT.OrdinaryDefineOwnProperty(env, O, P, Desc)
   local current = mt(env, O, '[[GetOwnProperty]]', P)
   local extensible = mt(env, O, '[[IsExtensible]]')
   return ObjectMT.ValidateAndApplyPropertyDescriptor(
      env, O, P, extensible, Desc, current
   )
end
ObjectMT['[[DefineOwnProperty]]'] = ObjectMT.OrdinaryDefineOwnProperty

function ObjectMT.ValidateAndApplyPropertyDescriptor(env, O, P, extensible, desc, current)
   local field = (not rawequal(O, Undefined)) and mt(env, P, 'toKey') or nil
   if current == nil then
      if extensible == false then return false end
      if desc:IsGenericDescriptor() or desc:IsDataDescriptor() then
         if field ~= nil then
            if desc:IsSimple(false) then
               local val = desc.value
               if val == nil then val = Undefined end
               rawset(O, field, val)
            else
               rawset(O, field, PropertyDescriptor:newData(desc))
            end
         end
      else
         if field ~= nil then
            rawset(O, field, PropertyDescriptor:newAccessor(desc))
         end
      end
      return true
   end
   if desc:IsEmpty() then return true end
   if current.configurable == false then
      if desc.configurable == true then return false end
      if desc.enumerable ~= nil and (desc.enumerable ~= current.enumerable) then
         return false
      end
   end
   if desc:IsGenericDescriptor() then
      -- no further validation required
   elseif current:IsDataDescriptor() ~= desc:IsDataDescriptor() then
      if current.configurable == false then return false end
      if current:IsDataDescriptor() then
         if field ~= nil then
            rawset(O, field, PropertyDescriptor:newAccessor(current))
         end
      else
         if field ~= nil then
            rawset(O, field, PropertyDescriptor:newData(current))
         end
      end
   elseif current:IsDataDescriptor() and desc:IsDataDescriptor() then
      if current.configurable == false and current.writable == false then
         if desc.writable == true then return false end
         if desc.value ~= nil and not mt(env, desc.value, 'SameValue', current.value) then
            return false
         end
         return true
      end
   else
      if current.configurable == false then
         if desc.set ~= nil and not mt(env, desc.set, 'SameValue', current.set) then
            return false
         end
         if desc.get ~= nil and not mt(env, desc.get, 'SameValue', current.get) then
            return false
         end
         return true
      end
   end
   if field ~= nil then
      local valOrDesc = rawget(O, field)
      if IsPropertyDescriptor(valOrDesc) then
         valOrDesc:setFrom(desc)
      elseif desc:IsSimple(true) then
         if desc.value ~= nil then
            rawset(O, field, desc.value)
         end
         -- bail early, because valOrDesc is a value not a PropertyDescriptor
         return true
      else
         -- valOrDesc is a value here...
         valOrDesc = PropertyDescriptor:newSimple(valOrDesc):setFrom(desc)
         -- ...and now it's a property descriptor
         rawset(O, field, valOrDesc)
      end
      -- if we've falled through, check once more if the resulting valOrDesc
      -- (guaranteed to be a PropertyDescriptor) is simple, and optimize if so
      if valOrDesc.value ~= nil and valOrDesc:IsSimple(false) then
         -- reoptimize if we've ended up with a simple field
         rawset(O, field, valOrDesc.value)
      end
   end
   return true
end

function JsValMT.ObjectDefineProperties(env)
   ThrowTypeError(env, "Can't define properties on non-object")
end
function ObjectMT.ObjectDefineProperties(env, O, Properties)
   local props = mt(env, Properties, 'ToObject')
   local keys = mt(env, props, '[[OwnPropertyKeys]]')
   local descriptors = {}
   for _,nextKey in ipairs(keys) do
      local propDesc = mt(env, props, '[[GetOwnProperty]]', nextKey)
      if propDesc ~= nil and propDesc.enumerable == true then
         local descObj = mt(env, props, 'Get', nextKey)
         local desc = mt(env, descObj, 'ToPropertyDescriptor')
         table.insert(descriptors, { key = nextKey, desc = desc })
      end
   end
   for _,pair in ipairs(descriptors) do
      mt(env, O, 'DefinePropertyOrThrow', pair.key, pair.desc)
   end
   return O
end

function ObjectMT.ArrayDefineOwnProperty(env, A, P, desc) -- 9.4.2.1
   local lengthStr = StringMT:intern('length')
   if mt(env, P, 'Type') == 'String' then
      if StringMT.equals(P, lengthStr) then
         return mt(env, A, 'ArraySetLength', desc)
      end
      local index = mt(env, P, 'ToUint32')
      if StringMT.equals(mt(env, index, 'ToString'), P) then
         -- P is an array index
         local oldLenDesc = mt(env, A, 'OrdinaryGetOwnProperty', lengthStr)
         local oldLen = oldLenDesc.value
         if index.value >= oldLen.value and oldLenDesc.writable == false then
            return false
         end
         local succeeded = mt(env, A, 'OrdinaryDefineOwnProperty', P, desc)
         if not succeeded then return false end
         if index.value >= oldLen.value then
            local newLenDesc = PropertyDescriptor:newData(oldLenDesc)
            newLenDesc.value = NumberMT:from(index.value + 1)
            succeeded = mt(
               env, A, 'OrdinaryDefineOwnProperty', lengthStr, newLenDesc
            )
            assert(succeeded)
         end
         return true
      end
   end
   return mt(env, A, 'OrdinaryDefineOwnProperty', P, desc)
end

function ObjectMT.ArraySetLength(env, A, desc)
   local lengthStr = StringMT:intern('length')
   if desc.value == nil then
      return mt(env, A, 'OrdinaryDefineOwnProperty', lengthStr, desc)
   end
   local newLenDesc = desc:clone()
   local newLen = mt(env, desc.value, 'ToUint32')
   local numberLen = mt(env, desc.value, 'ToNumber')
   if newLen.value ~= numberLen.value then
      error('RangeError') -- XXX should throw a new RangeError exception
   end
   newLenDesc.value = newLen
   local oldLenDesc = mt(env, A, 'OrdinaryGetOwnProperty', lengthStr)
   assert(oldLenDesc ~= nil)
   local oldLen = oldLenDesc.value
   if newLen.value >= oldLen.value then
      return mt(env, A, 'OrdinaryDefineOwnProperty', lengthStr, newLenDesc)
   end
   if oldLenDesc.writable == false then return false end
   local newWritable
   if newLenDesc.writable == nil or newLenDesc.writable == true then
      newWritable = true
   else
      -- defer setting writable in case any elements can't be deleted
      newWritable = false
      newLenDesc.writable = true
   end
   local succeeded = mt(
      env, A, 'OrdinaryDefineOwnProperty', lengthStr, newLenDesc
   )
   if not succeeded then return false end
   for i=oldLen.value-1, newLen.value, -1 do
      -- XXX this isn't quite right; in a sparse array we waste time trying
      -- to delete non-existant elements.  But it's close enough.
      local P = mt(env, NumberMT:from(i), 'ToPropertyKey')
      local deleteSucceeded = mt(env, A, '[[Delete]]', P)
      if not deleteSucceeded then
         newLenDesc = newLenDesc:clone()
         newLenDesc.value = NumberMT:from(i + 1)
         if not newWritable then newLenDesc.writable = false end
         mt(env, A, 'OrdinaryDefineOwnProperty', lengthStr, newLenDesc)
         return false
      end
   end
   if not newWritable then
      return mt(env, A, 'OrdinaryDefineOwnProperty', lengthStr,
                PropertyDescriptor:new{ writable = false })
   end
   return true
end

-- Additional methods on PropertyDescriptor
function PropertyDescriptor.IsCompatible(desc, extensible, current)
   return ObjectMT.ValidateAndApplyPropertyDescriptor(
      nil, Undefined, Undefined, extensible, desc, current
   )
end

function PropertyDescriptor:From(env, desc)
   local obj = ObjectMT:create(env, env.realm.ObjectPrototype)
   local mkProp = function(field, val)
      mt(env, obj, 'CreateDataPropertyOrThrow', StringMT:intern(field), val)
   end
   local toBool = function(b) if b then return True else return False end end
   if desc.value ~= nil then mkProp('value', desc.value) end
   if desc.writable ~= nil then mkProp('writable', toBool(desc.writable)) end
   if desc.get ~= nil then mkProp('get', desc.get) end
   if desc.set ~= nil then mkProp('get', desc.set) end
   if desc.enumerable ~= nil then mkProp('enumerable', toBool(desc.enumerable)) end
   if desc.configurable ~= nil then mkProp('configurable', toBool(desc.configurable)) end
   return obj
end

function ObjectMT.ToPropertyDescriptor(env, obj)
   if not mt(env, obj, 'IsObject') then
      ThrowTypeError(env, 'property descriptor not an object')
   end
   local desc = PropertyDescriptor:new{}
   local has = function(field)
      return mt(env, obj, 'HasProperty', StringMT:intern(field))
   end
   local get = function(field)
      return mt(env, obj, 'Get', StringMT:intern(field))
   end
   local getBool = function(field)
      return mt(env, get(field), 'ToBoolean').value
   end
   if has('enumerable') then desc.enumerable = getBool('enumerable') end
   if has('configurable') then desc.configurable = getBool('configurable') end
   if has('value') then desc.value = get('value') end -- can be Undefined
   if has('writable') then desc.writable = getBool('writable') end
   if has('get') then
      local getter = get('get')
      if (not mt(env, getter, 'IsCallable')) and not rawequal(getter, Undefined) then
         ThrowTypeError(env, 'getter is not callable')
      end
      desc.get = getter -- can be Undefined
   end
   if has('set') then
      local setter = get('set')
      if (not mt(env, setter, 'IsCallable')) and (not rawequal(setting, Undefined)) then
         ThrowTypeError(env, 'setter is not callable')
      end
      desc.set = setter
   end
   if desc.get ~= nil or desc.set ~= nil then
      if desc.value ~= nil or desc.writable ~= nil then
         ThrowTypeError(env, 'accessor or data descriptor, not both')
      end
   end
   return desc
end

-- Math
function JsValMT.__add(lval, rval, env) -- note optional env!
   assert(isJsVal(rval))
   local lprim = mt(env, lval, 'ToPrimitive')
   if mt(env, lprim, 'Type') == 'String' then
      -- ToPrimitive/ToString on rval done inside StringMT.__add
      return StringMT.__add(lprim, rval, env) -- no need for ToString on lprim
   end
   local rprim = mt(env, rval, 'ToPrimitive')
   if mt(env, rprim, 'Type') == 'String' then
      local lstr = mt(env, lprim, 'ToString')
      return StringMT.__add(lstr, rprim, env) -- no need for ToString on rprim
   end
   local lnum = mt(env, lprim, 'ToNumeric')
   local rnum = mt(env, rprim, 'ToNumeric') -- avoids a redundant ToPrimitive
   return lnum + rnum
end
copyToAll('__add')
function StringMT.__add(lstr, rstr, env)
   if getmetatable(rstr) ~= StringMT then
      assert(isJsVal(rstr))
      local rprim = mt(env, rstr, 'ToPrimitive')
      rstr = mt(env, rprim, 'ToString')
   end
   return StringMT:cons(lstr, rstr)
end
function NumberMT.__add(l, r, env)
   if getmetatable(r) ~= NumberMT then
      assert(isJsVal(r))
      local rprim = mt(env, r, 'ToPrimitive') -- may be redundant
      if mt(env, rprim, 'Type') == 'String' then
         -- whoops, bail to string + string case!
         local lstr = mt(env, l, 'ToString')
         return StringMT.__add(lstr, rprim, env)
      end
      r = mt(env, rprim, 'ToNumeric')
   end
   return NumberMT:from(l.value + r.value)
end

function JsValMT.__sub(lval, rval, env) -- note optional env!
   local lnum = mt(env, lval, 'ToNumeric')
   local rnum = mt(env, rval, 'ToNumeric')
   if mt(env, lnum, 'Type') ~= mt(env, rnum, 'Type') then
      ThrowTypeError(env, 'bad types for subtraction')
   end
   assert(getmetatable(lnum) == NumberMT)
   return NumberMT:from(lnum.value - rnum.value)
end
copyToAll('__sub')
function NumberMT.__sub(l, r, env)
   if getmetatable(r) ~= NumberMT then
      r = mt(env, r, 'ToNumeric')
   end
   return NumberMT:from(l.value - r.value)
end

function JsValMT.__mul(lval, rval, env) -- note optional env!
   local lnum = mt(env, lval, 'ToNumeric')
   local rnum = mt(env, rval, 'ToNumeric')
   if mt(env, lnum, 'Type') ~= mt(env, rnum, 'Type') then
      ThrowTypeError(env, 'bad types for multiplication')
   end
   assert(getmetatable(lnum) == NumberMT)
   return NumberMT:from(lnum.value * rnum.value)
end
copyToAll('__mul')
function NumberMT.__mul(l, r, env)
   if getmetatable(r) ~= NumberMT then
      r = mt(env, r, 'ToNumeric')
   end
   return NumberMT:from(l.value * r.value)
end

-- Note that the order in which we call 'ToPrimitive' is a slight variance
-- from the JS spec -- EcmaScript is strict about calling it on the left
-- operand first, then the right operand -- but our turtlescript compiler
-- can swap operands in the interest of simplifying the bytecode operation.
function JsValMT.__lt(lval, rval, env) -- note optional env!
   local lnum = mt(env, lval, 'ToPrimitive', 'number')
   local rnum = mt(env, rval, 'ToPrimitive', 'number')
   -- if *both* are strings, we do a string comparison
   if mt(env, lnum, 'Type') == 'String' and mt(env, rnum, 'Type') == 'String' then
      return StringMT.__lt(lval, rval, env)
   end
   -- otherwise, a numerical comparison (skipping some BigInt support here)
   lnum = mt(env, lnum, 'ToNumeric')
   rnum = mt(env, rnum, 'ToNumeric')
   return NumberMT.__lt(lnum, rnum, env)
end
copyToAll('__lt')
function StringMT.__lt(l, r, env)
   if getmetatable(r) ~= StringMT then
      -- this will be a numeric comparison.
      return JsValMT.__lt(l, r, env)
   end
   l = StringMT:flatten(l).suffix
   r = StringMT:flatten(r).suffix
   return l < r -- This is UTF-16 but I think it works out correctly
end
function NumberMT.__lt(l, r, env)
   if getmetatable(r) ~= NumberMT then
      r = mt(env, r, 'ToPrimitive', 'number')
      r = mt(env, r, 'ToNumeric')
   end
   return l.value < r.value
end

function JsValMT.__le(lval, rval, env) -- note optional env!
   local lnum = mt(env, lval, 'ToPrimitive', 'number')
   local rnum = mt(env, rval, 'ToPrimitive', 'number')
   -- if *both* are strings, we do a string comparison
   if mt(env, lnum, 'Type') == 'String' and mt(env, rnum, 'Type') == 'String' then
      return StringMT.__le(lval, rval, env)
   end
   -- otherwise, a numerical comparison (skipping some BigInt support here)
   lnum = mt(env, lnum, 'ToNumeric')
   rnum = mt(env, rnum, 'ToNumeric')
   return NumberMT.__le(lnum, rnum, env)
end
copyToAll('__le')
function StringMT.__le(l, r, env)
   if getmetatable(r) ~= StringMT then
      -- this will be a numeric comparison.
      return JsValMT.__le(l, r, env)
   end
   l = StringMT:flatten(l).suffix
   r = StringMT:flatten(r).suffix
   return l <= r -- This is UTF-16 but I think it works out correctly
end
function NumberMT.__le(l, r, env)
   if getmetatable(r) ~= NumberMT then
      r = mt(env, r, 'ToPrimitive', 'number')
      r = mt(env, r, 'ToNumeric')
   end
   return l.value <= r.value
end

function JsValMT.__eq(l, r, env)
   if isJsVal(l) ~= isJsVal(r) then return false end
   if getmetatable(l) == NumberMT then return NumberMT.__eq(l, r, env) end
   return mt(env, l, 'SameValue', r)
end
function NumberMT.__eq(l, r, env)
   if getmetatable(r) ~= NumberMT then return false end
   return l.value == r.value -- matches Number::equal (6.1.6.1.13)
end
function StringMT.__eq(l, r, env) -- fast path
   if getmetatable(r) ~= StringMT then return false end
   return StringMT:flatten(l).suffix == StringMT:flatten(r).suffix
end

function UndefinedMT.SameValue(env, l, r)
   if getmetatable(r) ~= UndefinedMT then return false end
   return true
end
function NullMT.SameValue(env, l, r)
   if getmetatable(r) ~= NullMT then return false end
   return true
end
function BooleanMT.SameValue(env, l, r)
   if getmetatable(r) ~= BooleanMT then return false end
   return l.value == r.value
end
function StringMT.SameValue(env, l, r)
   if getmetatable(r) ~= StringMT then return false end
   return StringMT.equals(l, r)
end
function SymbolMT.SameValue(env, l, r)
   if getmetatable(r) ~= StringMT then return false end
   return rawequal(l, r)
end
function ObjectMT.SameValue(env, l, r)
   if mt(env, r, 'Type') ~= 'Object' then return false end -- allow subclassing
   return rawequal(l, r)
end
function NumberMT.SameValue(env, l, r) -- see 6.1.6.1.14
   if getmetatable(r) ~= NumberMT then return false end
   local x, y = l.value, r.value
   if x ~= x and y ~= y then return true end -- both x and y are NaN
   if x == 0 and y == 0 then return (1/x) == (1/y) end -- distinguish +/- 0
   return (x == y)
end

function StringMT.equals(l, r)
   return StringMT:flatten(l).suffix == StringMT:flatten(r).suffix
end

function StringMT.IsZeroLength(s)
   local u8 = s.utf8
   if u8 ~= nil then return #u8 == 0 end -- fast path!
   for _,ss in ipairs{ s.suffix, s.prefix } do -- suffix's more likely non-nil
      if ss ~= nil then
         if type(ss) == 'string' then
            if #ss > 0 then return false end
         else
            if not StringMT.IsZeroLength(ss) then return false end
         end
      end
   end
   return true
end

-- Object utilities (lua interop)
function ObjectMT:__index(key)
   local env = rawget(self, DEFAULTENV)
   local jskey = mt(env, fromLua(env, key), 'ToPropertyKey')
   return toLua(env, mt(env, self, 'GetV', jskey))
end
function ObjectMT:__newindex(key, value)
   local env = rawget(self, DEFAULTENV)
   local jskey = mt(env, fromLua(env, key), 'ToPropertyKey')
   local jsval = fromLua(env, value)
   mt(env, self, '[[Set]]', jskey, jsval, self)
end

-- String utilities (lua interop)
function StringMT:__len()
   if self.prefix ~= nil then
      StringMT:flatten(self)
   end
   return (#self.suffix) >> 1 -- UTF-16 length
end

-- UTF16 to UTF8 string conversion
function StringMT:__tostring()
   local u8 = self.utf8
   if u8 ~= nil then return u8 end -- fast path for constants
   s = StringMT:flatten(self).suffix -- UTF-16 native string
   local result = {}
   local len = #s
   local surrogate = false
   for i=1,len,2 do
      local hi,lo = string.byte(s, i, i+1)
      local code = (hi << 8) | lo
      if surrogate ~= false then
         if code >= 0xDC00 and code <= 0xDFFF then
            code = (surrogate - 0xDB00) * 0x400 + (code - 0xDC00) + 0x10000;
            surrogate = false
         else
            assert(false, 'bad utf-16')
         end
         table.insert(result, code)
      elseif code >= 0xDB00 and code <= 0xDBFF and (i+2) < len then
         surrogate = code
      else
         table.insert(result, code)
      end
   end
   assert(surrogate == false, 'bad utf-16')
   u8 = utf8.char(table.unpack(result))
   -- speed up future invocations!
   self.utf8 = u8
   return u8
end
function StringMT.toKey(env, s)
   local key = rawget(s, 'key')
   if key ~= nil then return key end -- fast path
   key = 'js@' .. StringMT.__tostring(s)
   rawset(s, 'key', key)
   return key
end

return {
   Undefined = Undefined,
   Null = Null,
   True = True,
   False = False,
   PropertyDescriptor = PropertyDescriptor,
   extendObj = function(obj)
      setmetatable(obj, extendMT(getmetatable(obj)))
   end,
   invokePrivate = mt,
   isJsVal = isJsVal,
   fromLua = fromLua,
   toLua = toLua,
   convertUtf16ToUtf8 = function(utf16)
      return tostring(StringMT:cons(nil, utf16))
   end,
   stringToUtf16 = function(s) return StringMT:flatten(s).suffix end,
   Type = function(jsval) return mt(nil, jsval, 'Type') end,
   newBoolean = function(b) if b then return True else return False end end,
   newNumber = function(val) return NumberMT:from(val) end,
   newString = function(s) return StringMT:fromUTF8(s) end,
   newStringFromUtf16 = function(s) return StringMT:cons(nil, s) end,
   newStringIntern = function(s) return StringMT:intern(s) end,
   newObject = function(env, proto)
      if proto == nil then proto = env.realm.ObjectPrototype end
      return ObjectMT:create(env, proto)
   end,
   newFunction = function(env, fields)
      -- XXX this should match OrdinaryFunctionCreate from ECMAScript spec
      local f = ObjectMT:create(env, env.realm.FunctionPrototype)
      -- hidden fields of callable function objects
      rawset(f, PARENTFRAME, fields.parentFrame)
      rawset(f, VALUE, { modul = fields.modul, func = fields.func })
      -- user-visible fields
      mt(env, f, 'OrdinaryDefineOwnProperty', StringMT:intern('name'),
         PropertyDescriptor:newData{value = fields.func.name, configurable=true}
      )
      mt(env, f, 'OrdinaryDefineOwnProperty', StringMT:intern('length'),
         PropertyDescriptor:newData{value = NumberMT:from(fields.func.nargs), configurable=true}
      )
      return f
   end,
   newFrame = function(env, parentFrame, this, arguments)
      local nFrame = ObjectMT:create(env, parentFrame)
      mt(env, nFrame, '[[Set]]', StringMT:intern('this'), this, nFrame)
      mt(env, nFrame, '[[Set]]', StringMT:intern('arguments'), arguments, nFrame)
      -- this is used by the binterp compiler to avoid actual inheritance of
      -- frame objects, but we don't support the __proto__ field yet (although
      -- we do support actual inheritance of frame objects!).  Anyway, fake
      -- it until you make it.
      mt(env, nFrame, '[[Set]]', StringMT:intern('__proto__'), parentFrame, nFrame)
      return nFrame
   end,
   privateFields = {
      PARENTFRAME = PARENTFRAME,
      VALUE = VALUE,
      ISAPPLY = ISAPPLY,
      STRINGDATA = STRINGDATA,
      BOOLEANDATA = BOOLEANDATA,
      NUMBERDATA = NUMBERDATA,
   }
}
