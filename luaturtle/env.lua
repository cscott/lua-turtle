-- JavaScript execution environment
-- Consists of a realm, well-known symbols, etc
local ops = require('luaturtle.ops')
local jsval = require('luaturtle.jsval')

function nyi(which)
   return function()
      error("Not yet implemented: " .. which)
   end
end

-- Bytecode interpreter execution state
local State = {}
State.__index = State

function State:new(parent, frame, modul, func)
   local o = {
      parent = parent,
      frame = frame,
      stack = {},
      pc = 1, -- lua indexing is 1-based
      -- from bytecode file
      modul = modul,
      func = func
   }
   setmetatable(o, self)
   return o
end

function State:__tostring()
   local s = ''
   for k,v in pairs(self) do
      s = s .. k .. '=' .. tostring(v) .. ','
   end
   return 'State{' .. s .. '}'
end

function State:push(v)
   table.insert(self.stack, v)
end

function State:pop()
   return table.remove(self.stack)
end

function State:getnext()
   local n = self.func.bytecode[self.pc]
   self.pc = self.pc + 1
   return n
end


-- JavaScript execution environment
-- Consists of a realm, well-known symbols, etc.
-- (Also the bytecode interpreter!)
local Env = {}
Env.__index = Env

function Env:new()
   local env = {
      realm = {},
      symbols = {}
   }
   setmetatable(env, self)

   local function setRealm(name, debugName, obj)
      rawset(obj, jsval.privateSlots.DEBUGNAME, debugName)
      env.realm[name] = obj
   end

   -- %ObjectPrototype%, the parent of all Objects
   local ObjectPrototype = jsval.newObject(env, jsval.Null)
   jsval.extendObj(ObjectPrototype)
   getmetatable(ObjectPrototype)['[[SetPrototypeOf]]'] =
      getmetatable(ObjectPrototype)['SetImmutablePrototype']
   setRealm('ObjectPrototype', '%ObjectPrototype%', ObjectPrototype)

   -- 19.1.1 The Object Constructor
   local Object = env:addNativeFunc(nil, 'Object', 1, function(this, args, newTarget, activeFunc)
     if newTarget ~= nil and newTarget ~= activeFunc then
        return jsval.invokePrivate(env, newTarget, 'OrdinaryCreateFromConstructor', ObjectPrototype)
     end
     local value = args[1]
     if rawequal(value, jsval.Undefined) or rawequal(value, jsval.Null) then
        return jsval.newObject(env, ObjectPrototype)
     end
     return jsval.invokePrivate(env, value, 'ToObject')
   end)
   env:mkFrozen(Object, 'prototype', ObjectPrototype)
   env:mkHidden(ObjectPrototype, 'constructor', Object) -- cycles, whee!
   setRealm('Object', '%Object%', Object)

   local FunctionPrototype = jsval.newObject(env, ObjectPrototype)
   env:mkDataDesc(FunctionPrototype, 'name', { value = '', configurable = true })
   env:mkDataDesc(FunctionPrototype, 'length', { value = 0, configurable = true })
   setRealm('FunctionPrototype', '%Function.prototype%', FunctionPrototype)

   -- 19.2.1 The Function Constructor
   local Function = jsval.newObject(env, FunctionPrototype)
   env:mkDataDesc(Function, 'name', { value = 'Function', configurable = true })
   env:mkDataDesc(Function, 'length', { value = 1, configurable = true })
   env:mkFrozen(Function, 'prototype', FunctionPrototype)
   setRealm('Function', '%Function%', Function)

   -- 19.3 Boolean Objects
   local BooleanPrototype = jsval.newObject(env, ObjectPrototype)
   rawset(BooleanPrototype, jsval.privateSlots.BOOLEANDATA, jsval.False)
   setRealm('BooleanPrototype', '%BooleanPrototype%', BooleanPrototype)

   local Boolean = env:addNativeFunc(nil, 'Boolean', 1, function(this, args, newTarget)
     local b = jsval.invokePrivate(env, args[1] or jsdef.Undefined, 'ToBoolean')
     if newTarget == nil then return b end
     local proto = jsval.invokePrivate(env, newTarget, 'GetPrototypeFromConstructor', BooleanPrototype)
     return jsval.invokePrivate(env, b, 'ToObject', proto)
   end)
   env:mkFrozen(Boolean, 'prototype', BooleanPrototype)
   env:mkHidden(BooleanPrototype, 'constructor', Boolean) -- cycles, whee!
   setRealm('Boolean', '%Boolean%', Boolean)

   -- 19.5 Error objects
   local ErrorPrototype = jsval.newObject(env, ObjectPrototype)
   env:mkHidden(ErrorPrototype, 'name', 'Error')
   env:mkHidden(ErrorPrototype, 'message', '')
   setRealm('ErrorPrototype', '%ErrorPrototype%', ErrorPrototype)

   local Error = env:addNativeFunc(nil, 'Error', 1, function(this, args, newTarget, activeFunc)
     local newTarget = newTarget or activeFunc or jsval.Undefined
     local O = jsval.invokePrivate(env, newTarget, 'OrdinaryCreateFromConstructor', ErrorPrototype)
     rawset(O, jsval.privateSlots.ERRORDATA, jsval.Undefined)
     if args[1] ~= nil then
        local msg = mt(env, args[1], 'ToString')
        env:mkHidden(O, 'message', msg)
     end
     return O
   end)
   env:mkFrozen(Error, 'prototype', ErrorPrototype)
   env:mkHidden(ErrorPrototype, 'constructor', Error) -- cycles, whee!
   setRealm('Error', '%Error%', Error)

   local nativeErrors = {
      'EvalError', 'RangeError', 'ReferenceError', 'SyntaxError',
      'TypeError', 'URIError'
   }
   for _,nativeErrorName in ipairs(nativeErrors) do
      local NativeErrorPrototype = jsval.newObject(env, ErrorPrototype)
      env:mkHidden(NativeErrorPrototype, 'name', nativeErrorName)
      env:mkHidden(NativeErrorPrototype, 'message', '')
      setRealm(nativeErrorName .. 'Prototype', '%' .. nativeErrorName .. 'Prototype%', NativeErrorPrototype)

      local NativeError = env:addNativeFunc(nil, nativeErrorName, 1, function(this, args, newTarget, activeFunc)
        local newTarget = newTarget or activeFunc or jsval.Undefined
        local O = jsval.invokePrivate(env, newTarget, 'OrdinaryCreateFromConstructor', NativeErrorPrototype)
        rawset(O, jsval.privateSlots.ERRORDATA, jsval.Undefined)
        if args[1] ~= nil then
           local msg = mt(env, args[1], 'ToString')
           env:mkHidden(O, 'message', msg)
        end
        return O
      end)
      env:mkFrozen(NativeError, 'prototype', NativeErrorPrototype)
      env:mkHidden(NativeErrorPrototype, 'constructor', NativeError) -- cycles, whee!
      setRealm(nativeErrorName, '%' .. nativeErrorName .. '%', NativeError)
   end

   -- 20.1.3 Properties of the Number Prototype Object
   local NumberPrototype = jsval.newObject(env, ObjectPrototype)
   rawset(NumberPrototype, jsval.privateSlots.NUMBERDATA, jsval.newNumber(0))
   setRealm('NumberPrototype', '%NumberPrototype%', NumberPrototype)

   -- 20.1.1 The Number Constructor
   local Number = env:addNativeFunc(nil, 'Number', 1, function(this, args, newTarget)
     local value = args[1] or jsval.newNumber(0)
     local n = jsval.invokePrivate(env, value, 'ToNumeric')
     -- XXX BigInt support
     if newTarget == nil then return n end
     local proto = jsval.invokePrivate(env, newTarget, 'GetPrototypeFromConstructor', NumberPrototype)
     return jsval.invokePrivate(env, n, 'ToObject', proto)
   end)
   env:mkFrozen(Number, 'prototype', NumberPrototype)
   env:mkHidden(NumberPrototype, 'constructor', Number) -- cycles, whee!
   setRealm('Number', '%Number%', Number)

   -- 20.3 The Math object
   local Math = jsval.newObject(env, ObjectPrototype)
   setRealm('Math', '%Math%', Math)

   -- 21.1.3 Properties of the String Prototype Object
   local StringPrototype = jsval.newObject(env, ObjectPrototype)
   jsval.extendObj(StringPrototype)
   rawset(StringPrototype, jsval.privateSlots.STRINGDATA, jsval.newStringIntern(''))
   env:mkFrozen(StringPrototype, 'length', 0)
   getmetatable(StringPrototype)['[[GetOwnProperty]]'] = function(env, S, P)
      local desc = jsval.invokePrivate(env, S, 'OrdinaryGetOwnProperty', P)
      if desc ~= nil then return desc end
      return jsval.invokePrivate(env, S, 'StringGetOwnProperty', P)
   end
   getmetatable(StringPrototype)['[[DefineOwnProperty]]'] = function(env, S, P, desc)
      local stringDesc = jsval.invokePrivate(env, S, 'StringGetOwnProperty', P)
      if stringDesc ~= nil then
         local extensible = jsval.invokePrivate(env, S, 'OrdinaryIsExtensible')
         return desc:IsCompatible(extensible, stringDesc)
      end
      return jsval.invokePrivate(env, S, 'OrdinaryDefineOwnProperty', P, desc)
   end
   getmetatable(StringPrototype)['[[OwnPropertyKeys]]'] = nyi('9.4.3.3')
   setRealm('StringPrototype', '%StringPrototype%', StringPrototype)

   -- 21.1.1 The String constructor
   local String = env:addNativeFunc(nil, 'String', 1, function(this, args, newTarget)
     local value = args[1]
     local s
     if value == nil then
        s = jsval.newStringIntern('')
     elseif newTarget == nil and jsval.Type(value) == 'Symbol' then
        return jsval.invokePrivate(env, value, 'SymbolDescriptiveString')
     else
        s = jsval.invokePrivate(env, value, 'ToString')
     end
     if newTarget == nil then return s end
     local proto = jsval.invokePrivate(env, newTarget, 'GetPrototypeFromConstructor', StringPrototype)
     return jsval.invokePrivate(env, s, 'StringCreate', proto)
   end)
   env:mkFrozen(String, 'prototype', StringPrototype)
   env:mkHidden(StringPrototype, 'constructor', String) -- cycles, whee!
   setRealm('String', '%String%', String)

   -- 22.1.3 Properties of the Array Prototype object
   local ArrayPrototype = jsval.newObject(env, ObjectPrototype)
   jsval.extendObj(ArrayPrototype)
   env:mkDataDesc(ArrayPrototype, 'length', { value = 0, writable = true })
   getmetatable(ArrayPrototype)['[[DefineOwnProperty]]'] =
      getmetatable(ArrayPrototype)['ArrayDefineOwnProperty']
   setRealm('ArrayPrototype', '%ArrayPrototype%', ArrayPrototype)

   -- 22.1.1 The Array constructor
   local Array = jsval.newObject(env, FunctionPrototype)
   env:mkFrozen(Array, 'prototype', ArrayPrototype)
   env:mkDataDesc(Array, 'name', { value = 'Array', configurable = true })
   env:mkDataDesc(Array, 'length', { value = 1, configurable = true })
   setRealm('Array', '%Array%', Array)

   -- Not in ECMAScript but useful: console!
   local ConsolePrototype = jsval.newObject(env, ObjectPrototype)
   env.realm.ConsolePrototype = ConsolePrototype
   local Console = jsval.newObject(env, ConsolePrototype)
   setRealm('Console', '%Console%', Console)

   -- Native methods
   local function RequireObjectCoercible(arg)
      if rawequal(arg, jsval.Null) or rawequal(arg, jsval.Undefined) then
         error(env:newTypeError('this not coercible to object'))
      end
      return arg
   end
   env:addNativeFunc(BooleanPrototype, 'valueOf', 0, function(this, args)
      return jsval.invokePrivate(env, this, 'thisBooleanValue')
   end)
   env:addNativeFunc(ConsolePrototype, 'log', 0, function(this, args)
      local sargs = {}
      for _,v in ipairs(args) do
         table.insert(sargs, tostring(jsval.invokePrivate(env, v, 'ToString')))
      end
      print(table.concat(sargs, ' '))
      return jsval.Undefined
   end)
   env:addNativeFunc(ErrorPrototype, 'toString', 0, function(this, args)
      local O = this
      if jsval.Type(O) ~= 'Object' then
         error(env:newTypeError('not object'))
      end
      local name = jsval.invokePrivate(env, O, 'Get', jsval.newStringIntern('name'))
      if rawequal(name, jsval.Undefined) then
         name = jsval.newStringIntern('Error')
      else
         name = jsval.invokePrivate(env, name, 'ToString')
      end
      local msg = jsval.invokePrivate(env, O, 'Get', jsval.newStringIntern('message'))
      if rawequal(msg, jsval.Undefined) then
         msg = jsval.newStringIntern('')
      else
         msg = jsval.invokePrivate(env, msg, 'ToString')
      end
      if rawequal(jsval.invokePrivate(env, name, 'ToBoolean'), jsval.False) then
         return msg
      end
      if rawequal(jsval.invokePrivate(env, msg, 'ToBoolean'), jsval.False) then
         return name
      end
      return name + jsval.newStringIntern(': ') + msg
   end)
   env:addNativeFunc(Math, 'abs', 1, function(this, args)
      local n = jsval.invokePrivate(env, args[1] or jsval.Undefined, 'ToNumber')
      return jsval.newNumber(math.abs(jsval.toLua(env, n)))
   end)
   env:addNativeFunc(Math, 'floor', 1, function(this, args)
      local n = jsval.invokePrivate(env, args[1] or jsval.Undefined, 'ToNumber')
      n = jsval.toLua(env, n)
      -- special case for -0.0
      if n == 0 and (1/n) == (-1/0) then return jsval.newNumber(n) end
      return jsval.newNumber(math.floor(n))
   end)
   env:addNativeFunc(NumberPrototype, 'valueOf', 0, function(this, args)
      return jsval.invokePrivate(env, this, 'thisNumberValue')
   end)
   env:addNativeFunc(Object, 'create', 2, function(this, args)
     local O = args[1] or jsval.Undefined
     local Properties = args[2] or jsval.Undefined
     if O ~= jsval.Null and jsval.Type(O) ~= 'Object' then
        error(env:newTypeError('prototype not an object or null'))
     end
     local obj = jsval.newObject(env, O)
     if rawequal(Properties, jsval.Undefined) then return obj end
     return jsval.invokePrivate(env, obj, 'ObjectDefineProperties', Properties)
   end)
   env:addNativeFunc(Object, 'defineProperties', 2, function(this, args)
     local O = args[1] or jsval.Undefined
     local Properties = args[2] or jsval.Undefined
     return jsval.invokePrivate(env, O, 'ObjectDefineProperties', Properties)
   end)
   env:addNativeFunc(Object, 'defineProperty', 3, function(this, args)
     local O = args[1] or jsval.Undefined
     local P = args[2] or jsval.Undefined
     local Attributes = args[3] or jsval.Undefined
     if jsval.Type(O) ~= 'Object' then
        error(env:newTypeError('not an object'))
     end
     local key = jsval.invokePrivate(env, P, 'ToPropertyKey')
     local desc = jsval.invokePrivate(env, Attributes, 'ToPropertyDescriptor')
     jsval.invokePrivate(env, O, 'DefinePropertyOrThrow', key, desc)
     return O
   end)
   -- Object.Try / Object.Throw -- turtlescript extension!
   env:addNativeFunc(Object, 'Try', 4, function(this, args)
     local innerThis = args[1] or jsval.Undefined
     local bodyBlock = args[2] or jsval.Undefined
     local catchBlock = args[3] or jsval.Undefined
     local finallyBlock = args[4] or jsval.Undefined
     local status, rv = env:interpretFunction(bodyBlock, innerThis, {})
     if not status then -- exception thrown! invoke catchBlock!
        if not jsval.isJsVal(rv) then error(rv) end -- lua exception, rethrow
        -- print('EXCEPTION CAUGHT!', rv)
        if jsval.Type(catchBlock) == 'Object' then
           status, rv = env:interpretFunction( catchBlock, innerThis, { rv } )
           -- ignore return value of catch block (not ideal)
           if status then rv = jsval.Undefined end
        end
     end
     if jsval.Type(finallyBlock)=='Object' then
        nyi('finally block')()
     end
     -- rethrow if exception uncaught (or thrown during catch)
     if not status then error(rv) end
     return rv
   end)
   env:addNativeFunc(Object, 'Throw', 1, function(this, args)
     local ex = args[1] or jsval.Undefined
     error(ex) -- native throw!
   end)

   env:addNativeFunc(ObjectPrototype, 'hasOwnProperty', 1, function(this, args)
     local V = args[1] or jsval.Undefined
     local P = jsval.invokePrivate(env, V, 'ToPropertyKey')
     local O = jsval.invokePrivate(env, this, 'ToObject')
     return jsval.invokePrivate(env, O, 'HasOwnProperty', P)
   end)
   env:addNativeFunc(ObjectPrototype, 'toString', 0, function(this, args)
     if rawequal(this, jsval.Undefined) then
        return jsval.newStringIntern('[object Undefined]')
     elseif rawequal(this, jsval.Null) then
        return jsval.newStringIntern('[object Null]')
     end
     local O = jsval.invokePrivate(env, this, 'ToObject')
     local isArray = jsval.invokePrivate(env, O, 'IsArray')
     local builtinTag
     if isArray then
        builtinTag = 'Array'
     elseif rawget(O, jsval.privateSlots.PARAMETERMAP) ~= nil then
        builtinTag = 'Arguments'
     elseif rawget(O, jsval.privateSlots.CALL) ~= nil then
        builtinTag = 'Function'
     elseif rawget(O, jsval.privateSlots.ERRORDATA) ~= nil then
        builtinTag = 'Error'
     elseif rawget(O, jsval.privateSlots.BOOLEANDATA) ~= nil then
        builtinTag = 'Boolean'
     elseif rawget(O, jsval.privateSlots.NUMBERDATA) ~= nil then
        builtinTag = 'Number'
     elseif rawget(O, jsval.privateSlots.STRINGDATA) ~= nil then
        builtinTag = 'String'
     -- XXX Date and RegExp, too
     else
        builtinTag = 'Object'
     end
     local tag = jsval.Undefined
     if env.symbols.toStringTag ~= nil then -- XXX symbols NYI
        tag = mt(env, O, 'Get', env.symbols.toStringTag)
     end
     if jsval.Type(tag) ~= 'String' then tag = jsval.newString(builtinTag) end
     return jsval.newStringIntern('[object ') + tag + jsval.newStringIntern(']')
   end)
   env:addNativeFunc(ObjectPrototype, 'valueOf', 0, function(this, args)
     return jsval.invokePrivate(env, this, 'ToObject')
   end)

   rawset(env:addNativeFunc(FunctionPrototype, 'call', 1, function(this, args)
     -- push arguments on stack and use 'invoke' bytecode op
     -- arg #0 is the function itself ('this')
     -- arg #1 is 'this' (for the invoked function)
     -- arg #2-#n are rest of arguments
     local nargs = { this } -- the function itself
     if #args == 0 then
        -- Ensure there's a 'this' value (for the invoked function);
        -- that's a non-optional argument
        table.insert(nargs, jsval.Undefined)
     else
        for i,v in ipairs(args) do
           table.insert(nargs, v)
        end
     end
     return nargs
   end), jsval.privateSlots.ISAPPLY, true)
   rawset(env:addNativeFunc(FunctionPrototype, 'apply', 2, function(this, args)
     -- push arguments on stack and use 'invoke' bytecode op
     -- arg #0 is the function itself ('this')
     -- arg #1 is 'this' (for the invoked function)
     -- arg #2 is rest of arguments, as JS array
     local nargs = { this, (args[1] or jsval.Undefined) }
     if #args > 1 then
        env:arrayEach(args[2], function(v) table.insert(nargs, v) end)
     end
     return nargs
   end), jsval.privateSlots.ISAPPLY, true)

   env:addNativeFunc(StringPrototype, 'charAt', 1, function(this, args)
     local O = RequireObjectCoercible(this)
     local S = jsval.invokePrivate(env, O, 'ToString')
     local pos = args[1] or jsval.Undefined
     local position = jsval.toLua(env, jsval.invokePrivate(env, pos, 'ToInteger'))
     local size = #S
     if position < 0 or position >= size then
        return jsval.newStringIntern('')
     end
     local start = (position << 1) + 1 -- 1-based indexing!
     local resultStr = string.sub(jsval.stringToUtf16(S), start, start + 1)
     return jsval.newStringFromUtf16(resultStr)
   end)
   env:addNativeFunc(StringPrototype, 'charCodeAt', 1, function(this, args)
     local O = RequireObjectCoercible(this)
     local S = jsval.invokePrivate(env, O, 'ToString')
     local pos = args[1] or jsval.Undefined
     local position = jsval.toLua(env, jsval.invokePrivate(env, pos, 'ToInteger'))
     local size = #S
     if position < 0 or position >= size then
        return jsval.newNumber(0/0) -- NaN
     end
     local start = (position << 1) + 1 -- 1-based indexing!
     local high,lo = string.byte(jsval.stringToUtf16(S), start, start + 1)
     return jsval.newNumber((high<<8) | lo)
   end)
   env:addNativeFunc(String, 'fromCharCode', 1, function(this, args)
     local length = #args
     local elements = {}
     local nextIndex = 0
     while nextIndex < length do
        local next = args[1 + nextIndex]
        local nextCU = jsval.toLua(env, jsval.invokePrivate(env, next, 'ToUint16'))
        table.insert(elements, string.char(nextCU >> 8, nextCU & 0xFF))
        nextIndex = nextIndex + 1
     end
     return jsval.newStringFromUtf16(table.concat(elements))
   end)
   env:addNativeFunc(StringPrototype, 'valueOf', 0, function(this, args)
      return jsval.invokePrivate(env, this, 'thisStringValue')
   end)
   return env
end

function Env:prettyPrint(jsv)
   if jsv == nil then return 'nil' end
   assert(jsval.isJsVal(jsv))
   local debugName = rawget(jsv, jsval.privateSlots.DEBUGNAME)
   if debugName ~= nil then return debugName end
   local s = jsval.invokePrivate(env, jsv, 'ToString')
   return tostring(s)
end

function Env:arrayCreate(luaArray, isArguments)
   local arr = jsval.newObject(self, self.realm.ArrayPrototype)
   self:mkDataDesc(arr, 'length', { value = 0, writable = true })
   setmetatable(arr, getmetatable(self.realm.ArrayPrototype))
   for i,v in ipairs(luaArray) do
      arr[i-1] = v
   end
   if isArguments == true then
      -- Mark this array as a special 'arguments array'
      -- Affects 'toString' mostly.
      rawset(arr, jsval.privateSlots.PARAMETERMAP, true)
   end
   return arr
end

function Env:arrayEach(arr, func)
   local len = jsval.invokePrivate(
      self, arr, 'Get', jsval.newStringIntern('length')
   )
   len = jsval.toLua(env, len)
   for i = 1, len do
      local key = jsval.invokePrivate(
         self, jsval.newNumber(i-1), 'ToPropertyKey'
      )
      local val = jsval.invokePrivate(
         self, arr, 'Get', key
      )
      func(val)
   end
end

function Env.newTypeError(env, msg)
   local O = jsval.newObject(env, env.realm.TypeErrorPrototype)
   rawset(O, jsval.privateSlots.ERRORDATA, jsval.Undefined)
   if msg ~= nil then
      msg = jsval.invokePrivate(env, jsval.fromLua(env, msg), 'ToString')
      env:mkHidden(O, 'message', msg)
   end
   return O
end

-- helper functions to create properties
function Env:mkFrozen(obj, name, value)
   self:mkDataDesc(
      obj, name,
      jsval.PropertyDescriptor:newData{ value = jsval.fromLua(self, value ) }
   )
end

function Env:mkHidden(obj, name, value)
   self:mkDataDesc(
      obj, name,
      jsval.PropertyDescriptor:newData{
         value = jsval.fromLua(self, value),
         writable = true,
         configurable = true,
   })
end

function Env:mkDataDesc(obj, name, desc)
   if getmetatable(desc) ~= jsval.PropertyDescriptor then
      desc = jsval.PropertyDescriptor:newData(desc)
      if desc.value ~= nil then desc.value = jsval.fromLua(self, desc.value) end
   end
   jsval.invokePrivate(
      self, obj, 'OrdinaryDefineOwnProperty', jsval.newStringIntern(name),
      desc
   )
end

function Env:addNativeFunc(obj, name, len, f)
   local myFunc = jsval.newObject(self, self.realm.FunctionPrototype)
   self:mkDataDesc(myFunc, 'name', { value = name, configurable = true })
   self:mkDataDesc(myFunc, 'length', { value = len, configurable = true })
   rawset(myFunc, jsval.privateSlots.PARENTFRAME, jsval.Null)
   rawset(myFunc, jsval.privateSlots.VALUE, f)
   if obj ~= nil then self:mkHidden(obj, name, myFunc) end
   rawset(myFunc, jsval.privateSlots.CALL, true) -- mark as callable
   return myFunc
end

function Env:makeTopLevelFrame(context, arguments)
   local frame = jsval.newFrame(
      self, jsval.Null, context, self:arrayCreate(arguments, true)
   )

   -- value properties of the global object
   self:mkHidden(frame, 'globalThis', frame)
   self:mkFrozen(frame, 'Infinity', 1/0)
   self:mkFrozen(frame, 'NaN', 0/0)
   self:mkFrozen(frame, 'undefined', jsval.Undefined)
   self:mkHidden(frame, 'console', self.realm.Console)
   self:addNativeFunc(frame, 'isFinite', 1, function(this, args)
     local number = args[1] or jsval.Undefined
     local num = jsval.invokePrivate(self, number, 'ToNumber')
     num = num.value
     if num ~= num then return jsval.False end -- NaN
     if num == 1/0 or num == -1/0 then return jsval.False end -- infinities
     return jsval.True
   end)
   self:addNativeFunc(frame, 'isNaN', 1, function(this, args)
     local number = args[1] or jsval.Undefined
     local num = jsval.invokePrivate(self, number, 'ToNumber')
     num = num.value
     if num ~= num then return jsval.True end -- NaN
     return jsval.False
   end)

   -- constructors
   self:mkHidden(frame, 'Array', self.realm.Array)
   self:mkHidden(frame, 'Boolean', self.realm.Boolean)
   self:mkHidden(frame, 'Error', self.realm.Error)
   self:mkHidden(frame, 'Function', self.realm.Function)
   self:mkHidden(frame, 'Math', self.realm.Math)
   self:mkHidden(frame, 'Number', self.realm.Number)
   self:mkHidden(frame, 'Object', self.realm.Object)
   self:mkHidden(frame, 'RangeError', self.realm.RangeError)
   self:mkHidden(frame, 'String', self.realm.String)
   self:mkHidden(frame, 'TypeError', self.realm.TypeError)

   return frame
end

local one_step = {
   [ops.PUSH_FRAME] = function(env, state)
      state:push(state.frame)
   end,
   [ops.PUSH_LITERAL] = function(env, state)
      state:push(state.modul.literals[1+state:getnext()]) -- 1-based indexing
   end,
   [ops.NEW_OBJECT] = function(env, state)
      state:push(jsval.newObject(env, env.realm.ObjectPrototype))
   end,
   [ops.NEW_ARRAY] = function(env, state)
      state:push(env:arrayCreate{})
   end,
   [ops.NEW_FUNCTION] = function(env, state)
      local arg1 = state:getnext()
      local func = state.modul.functions[arg1 + 1] -- 1-based indexing
      local f = jsval.newFunction(env, {
        parentFrame = state.frame, modul = state.modul, func = func
      })
      state:push(f)
   end,
   [ops.GET_SLOT_DIRECT] = function(env, state)
      local obj = state:pop()
      local name = state.modul.literals[1+state:getnext()] -- 1-based indexing
      -- we should really handle the ToPropertyKey conversion at compile time
      name = jsval.invokePrivate(env, name, 'ToPropertyKey') -- arg, slow
      local result = jsval.invokePrivate(env, obj, 'GetV', name)
      state:push(result)
   end,
   [ops.GET_SLOT_DIRECT_CHECK] = function(env, state)
      local obj = state:pop()
      local name = state.modul.literals[1+state:getnext()] -- 1-based indexing
      -- we should really handle the ToPropertyKey conversion at compile time
      name = jsval.invokePrivate(env, name, 'ToPropertyKey') -- arg, slow
      local result = jsval.invokePrivate(env, obj, 'GetV', name)
      if jsval.Type(result) ~= 'Object' then
         -- warn about unimplemented (probably library) functions
         print('Failing lookup of method ' .. env:prettyPrint(obj) .. '.' .. tostring(name) .. "\n")
      end
      state:push(result)
   end,
   [ops.GET_SLOT_INDIRECT] = function(env, state)
      local name = jsval.invokePrivate(env, state:pop(), 'ToPropertyKey')
      local obj = state:pop()
      local result = jsval.invokePrivate(env, obj, 'GetV', name)
      state:push(result)
   end,
   [ops.SET_SLOT_DIRECT] = function(env, state)
      local nval = state:pop()
      local name = state.modul.literals[1+state:getnext()] -- 1-based indexing
      local obj = state:pop()
      obj = jsval.invokePrivate(env, obj, 'ToObject')
      -- we should really handle the ToPropertyKey conversion at compile time
      name = jsval.invokePrivate(env, name, 'ToPropertyKey') -- arg, slow
      jsval.invokePrivate(env, obj, '[[Set]]', name, nval, obj)
   end,
   [ops.SET_SLOT_INDIRECT] = function(env, state)
      local nval = state:pop()
      local name = jsval.invokePrivate(env, state:pop(), 'ToPropertyKey')
      local obj = state:pop()
      obj = jsval.invokePrivate(env, obj, 'ToObject')
      jsval.invokePrivate(env, obj, '[[Set]]', name, nval, obj)
   end,
   [ops.INVOKE] = function(env, state)
      return env:invoke(state, state:getnext())
   end,
   [ops.RETURN] = function(env, state)
      local retval = state:pop()
      -- go up to the parent state
      state = state.parent
      state:push(retval)
      return state -- continue in parent state
   end,
   -- branches
   [ops.JMP] = function(env, state)
      state.pc = state:getnext() + 1 -- convert to 1-based indexing
   end,
   [ops.JMP_UNLESS] = function(env, state)
      local arg1 = state:getnext()
      local cond = state:pop()
      cond = jsval.invokePrivate(env, cond, 'ToBoolean')
      if rawequal(cond, jsval.False) then
         state.pc = arg1 + 1 -- convert to 1-based indexing
      end
   end,
   -- stack manipulation
   [ops.POP] = function(env, state)
      state:pop()
   end,
   [ops.DUP] = function(env, state)
      local top = state:pop()
      state:push(top)
      state:push(top)
   end,
   [ops.DUP2] = function(env, state)
      local top = state:pop()
      local nxt = state:pop()
      state:push(nxt)
      state:push(top)
      state:push(nxt)
      state:push(top)
   end,
   [ops.OVER] = function(env, state)
      local top = state:pop()
      local nxt = state:pop()
      state:push(top)
      state:push(nxt)
      state:push(top)
   end,
   [ops.OVER2] = function(env, state)
      local top = state:pop()
      local nx1 = state:pop()
      local nx2 = state:pop()
      state:push(top)
      state:push(nx2)
      state:push(nx1)
      state:push(top)
   end,
   [ops.SWAP] = function(env, state)
      local top = state:pop()
      local nxt = state:pop()
      state:push(top)
      state:push(nxt)
   end,
   -- unary operators
   [ops.UN_NOT] = function(env, state)
      local arg = state:pop()
      arg = jsval.invokePrivate(env, arg, 'ToBoolean')
      if rawequal(arg, jsval.True) then
         state:push(jsval.False)
      else
         state:push(jsval.True)
      end
   end,
   [ops.UN_MINUS] = function(env, state)
      local arg = state:pop()
      -- lua passes the same arg twice for unary operators
      state:push( getmetatable(arg).__unm(arg, arg, env) )
   end,
   [ops.UN_TYPEOF] = function(env, state)
      local arg = state:pop()
      state:push( jsval.invokePrivate(env, arg, 'typeof') )
   end,
   [ops.BI_EQ] = function(env, state)
      local right = state:pop()
      local left = state:pop()
      local result = getmetatable(left).__eq(left, right, env)
      state:push( jsval.newBoolean(result) )
   end,
   [ops.BI_GT] = function(env, state)
      local right = state:pop()
      local left = state:pop()
      -- Note that we flip the order of operands
      local result = getmetatable(right).__lt(right, left, env)
      state:push( jsval.newBoolean(result) )
   end,
   [ops.BI_GTE] = function(env, state)
      local right = state:pop()
      local left = state:pop()
      -- Note that we flip the order of operands
      local result = getmetatable(right).__le(right, left, env)
      state:push( jsval.newBoolean(result) )
   end,
   [ops.BI_ADD] = function(env, state)
      local right = state:pop()
      local left = state:pop()
      state:push( getmetatable(left).__add(left, right, env) )
   end,
   [ops.BI_SUB] = function(env, state)
      local right = state:pop()
      local left = state:pop()
      state:push( getmetatable(left).__sub(left, right, env) )
   end,
   [ops.BI_MUL] = function(env, state)
      local right = state:pop()
      local left = state:pop()
      state:push( getmetatable(left).__mul(left, right, env) )
   end,
   [ops.BI_DIV] = function(env, state)
      local right = state:pop()
      local left = state:pop()
      state:push( getmetatable(left).__div(left, right, env) )
   end,
}

function Env:interpretOne(state)
   local op = state:getnext()
   -- print(state.pc-2, ops.bynum[op]) -- convert back to 0-based pc indexing
   local nstate = one_step[op](self, state) or state
   return nstate
end

function Env:interpret(modul, func_id, frame)
   if frame == nil then
      frame = self:makeTopLevelFrame(jsval.Null, {})
   end
   local func = modul.functions[func_id + 1] -- 1-based indexing
   local top = State:new(nil, frame, modul, func)
   local state = State:new(top, frame, modul, func)
   while state.parent ~= nil do -- wait for state == top
      state = self:interpretOne(state)
   end
   return state:pop()
end

-- Invoke a function from the stack
function Env:invoke(state, nargs)
   -- collect arguments
   local nativeArgs = {}
   for i = 1,nargs do
      table.insert(nativeArgs, state:pop())
   end
   for i = 1,nargs>>1 do -- reverse array
      j = (nargs+1) - i
      nativeArgs[i],nativeArgs[j] = nativeArgs[j],nativeArgs[i]
   end
   -- collect 'this'
   local myThis = state:pop()
   -- get function object
   local func = state:pop()
   if jsval.Type(func) == 'Object' then
      return self:invokeInternal( state, func, myThis, nativeArgs )
   end
   error('Not a function at '..tostring(state.pc - 1)..' function '..tostring(state.func.id))
end

-- Invoke a function from the stack (after function object, context, and
-- arguments have been popped off the stack)
function Env:invokeInternal(state, func, myThis, args)
   -- assert that func is a function
   local parentFrame = rawget(func, jsval.privateSlots.PARENTFRAME)
   if parentFrame == nil then
      error(self:newTypeError('Not a function at ' .. state.pc))
   end
   local f = rawget(func, jsval.privateSlots.VALUE)
   if type(f) == 'function' then -- native function
      local rv = f(myThis, args)
      -- handle "apply-like" natives
      if rawget(func, jsval.privateSlots.ISAPPLY) == true then
         local nargs = 0
         for i,val in ipairs(rv) do
            state:push(val)
            nargs = nargs + 1
         end
         return self:invoke(state, nargs - 2)
      end
      -- XXX handle exceptions
      state:push(rv)
      return state
   end
   if type(f) == 'table' and f.modul ~= nil and f.func ~= nil then
      -- create new frame
      assert(jsval.Type(parentFrame) == 'Object')
      local nFrame = jsval.newFrame(
         self, parentFrame, myThis, self:arrayCreate(args, true)
      )
      -- construct new child state
      return State:new(state, nFrame, f.modul, f.func)
   end
   error('bad function object')
end

-- Returns a pair of status, result like pcall does
-- status is false if an exception was thrown (and result is the exception)
function Env:interpretFunction(func, this, args)
   -- assert that func is a function
   local parentFrame = rawget(func, jsval.privateSlots.PARENTFRAME)
   if parentFrame == nil then
      error(self:newTypeError('Not a function'))
   end
   local f = rawget(func, jsval.privateSlots.VALUE)
   if type(f) == 'function' then -- native function
      local rv = f(this, args)
      -- handle "apply-like" natives
      if rawget(func, jsval.privateSlots.ISAPPLY) == true then
         local nArgs = {}
         for i,val in ipairs(rv) do
            table.insert(nArgs, val)
         end
         local nFunction = table.remove(nArgs, 1)
         local nThis = table.remove(nArgs, 1)
         return self:interpretFunction(nFunction, nThis, nArgs)
      end
      return true, rv
   end
   if type(f) == 'table' and f.modul ~= nil and f.func ~= nil then
      assert(jsval.Type(parentFrame) == 'Object')
      -- Make a frame for the function invocation
      local nFrame = jsval.newFrame(
         self, parentFrame, this, self:arrayCreate(args, true)
      )
      -- Set up error-handling
      return xpcall(
         self.interpret, debug.traceback, self, f.modul, f.func.id, nFrame
      )
   end
   error('bad function object')
end

return Env
