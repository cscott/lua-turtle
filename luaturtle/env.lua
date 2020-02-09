-- JavaScript execution environment
-- Consists of a realm, well-known symbols, etc
local ops = require('luaturtle.ops')
local jsval = require('luaturtle.jsval')

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

   -- %ObjectPrototype%, the parent of all Objects
   local ObjectPrototype = jsval.newObject(env, jsval.Null)
   env.realm.ObjectPrototype = ObjectPrototype
   jsval.extendObj(ObjectPrototype)
   getmetatable(ObjectPrototype)['[[SetPrototypeOf]]'] =
      getmetatable(ObjectPrototype)['SetImmutablePrototype']

   env.realm.FunctionPrototype = jsval.newObject(env, ObjectPrototype)
   return env
end

function Env:arrayCreate(luaArray)
   -- XXX this is a hack, we need a proper Array type
   local arr = jsval.newObject(self, self.realm.ObjectPrototype)
   local max = 0
   for i,v in ipairs(luaArray) do
      arr[i-1] = v
      if i > max then max = i end
   end
   arr.length = max
   return arr
end

function Env:makeTopLevelFrame(context, arguments)
   local frame = jsval.newFrame(
      env, jsval.Null, context, self:arrayCreate(arguments)
   )

   -- constructors
   -- XXX
   return frame
end


local function nyi(which)
   return function()
      error("Not yet implemented: " .. which)
   end
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
      state:push(jsval.Array()) -- XXX
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
      local result = jsval.invokePrivate(env, obj, '[[Get]]', name)
      state:push(result)
   end,
   [ops.GET_SLOT_DIRECT_CHECK] = function(env, state)
      local obj = state:pop()
      local name = state.modul.literals[1+state:getnext()] -- 1-based indexing
      local result = jsval.invokePrivate(env, obj, '[[Get]]', name)
      if jsval.Type(result) ~= 'Object' then
         -- warn about unimplemented (probably library) functions
         print('Failing lookup of method ' .. tostring(name) .. "\n")
      end
      state:push(result)
   end,
   [ops.SET_SLOT_DIRECT] = function(env, state)
      local nval = state:pop()
      local name = state.modul.literals[1+state:getnext()] -- 1-based indexing
      local obj = state:pop()
      jsval.invokePrivate(env, obj, '[[Set]]', name, nval, obj)
   end,
   [ops.SET_SLOT_INDIRECT] = function(env, state)
      local nval = state:pop()
      local name = state:pop()
      local obj = state:pop()
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
      if cond == jsval.False then
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
   [ops.UN_NOT] = nyi('UN_NOT'),
   [ops.UN_MINUS] = function(env, state)
      local arg = state:pop()
      state:push( getmetatable(arg).__unm(arg, env) )
   end,
   [ops.UN_TYPEOF] = nyi('UN_TYPEOF'),
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
      local result = getmetatable(left).__lt(right, left, env)
      state:push( jsval.newBoolean(result) )
   end,
   [ops.BI_GTE] = function(env, state)
      local right = state:pop()
      local left = state:pop()
      -- Note that we flip the order of operands
      local result = getmetatable(left).__le(right, left, env)
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
   local frame2 = frame
   if frame2 == nil then
      frame2 = self:makeTopLevelFrame(jsval.Null, {})
   end
   local func = modul.functions[func_id + 1] -- 1-based indexing
   local top = State:new(nil, frame2, modul, func)
   local state = State:new(top, frame2, modul, func)
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
      j = (len+1) - i
      nativeArgs[i],nativeArgs[j] = nativeArgs[j],nativeArgs[i]
   end
   -- collect 'this'
   local myThis = state:pop()
   -- get function object
   local func = state:pop()
   if jsval.Type(func) == 'Object' then
      return self:invokeInternal( state, func, myThis, nativeArgs )
   end
   error('Not a function at '..tostring(state.pc)..' function '..tostring(state.func.id))
end

-- Invoke a function from the stack (after function object, context, and
-- arguments have been popped off the stack)
function Env:invokeInternal(state, func, myThis, args)
   -- assert that func is a function
   local parentFrame = rawget(func, jsval.privateFields.PARENTFRAME)
   if parentFrame == nil then
      error(env:newTypeError('Not a function at ' .. state.pc))
   end
   local f = rawget(func, jsval.privateFields.VALUE)
   if type(f) == 'function' then -- native function
      local rv = f(myThis, args)
      -- handle "apply-like" natives
      if rawget(func, jsval.privateFields.ISAPPLY) == true then
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
         env, parentFrame, myThis, self:arrayCreate(args)
      )
      -- construct new child state
      return State:new(state, nFrame, f.modul, f.func)
   end
   error('bad function object')
end

return Env
